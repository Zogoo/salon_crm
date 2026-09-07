class Client < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :preferred_location, class_name: "Location", optional: true
  belongs_to :merged_into_client, class_name: "Client", optional: true
  has_one  :client_preference, dependent: :destroy
  has_many :client_preference_versions, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error

  validates :first_name, :last_name, :phone, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "") }

  before_save :refresh_search_name

  scope :kept, -> { where(discarded_at: nil) }

  # No pg_trgm on SQLite (doc 08 §2), so search is LIKE over a lowercased
  # column plus an exact-ish phone match.
  scope :search, ->(q) {
    next all if q.blank?
    term = "%#{q.to_s.downcase.strip}%"
    digits = q.to_s.gsub(/[^\d]/, "")
    rel = where("search_name LIKE ?", term)
    rel = rel.or(where("phone LIKE ?", "%#{digits}%")) if digits.present?
    rel
  }

  def full_name = "#{first_name} #{last_name}"

  private

  def refresh_search_name
    self.search_name = "#{first_name} #{last_name} #{email}".downcase.strip
  end
end
