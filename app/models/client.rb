class Client < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :preferred_location, class_name: "Location", optional: true
  belongs_to :merged_into_client, class_name: "Client", optional: true
  has_one  :client_preference, dependent: :destroy
  has_many :client_preference_versions, dependent: :destroy
  has_many :appointments, dependent: :restrict_with_error
  has_many :orders, dependent: :nullify
  has_many :bought_gift_cards, class_name: "GiftCard", foreign_key: :buyer_client_id,
                               dependent: :nullify, inverse_of: :buyer_client
  has_many :received_gift_cards, class_name: "GiftCard", foreign_key: :recipient_client_id,
                                 dependent: :nullify, inverse_of: :recipient_client
  has_one  :membership, dependent: :destroy

  validates :first_name, :last_name, :phone, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  normalizes :email, with: ->(e) { e.strip.downcase }
  # Doc 02 §5: phone is normalised to E.164 on write. It is the client's
  # identity, the front desk's search key and the SMS destination, so
  # "(312) 555-0101" and "+13125550101" must resolve to one client — otherwise
  # a data import quietly creates a second copy of everybody.
  normalizes :phone, with: ->(p) { Client.to_e164(p) }

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

  # US numbers only, which is all four locations. Anything already carrying a
  # "+" is left alone rather than mangled.
  def self.to_e164(raw)
    value = raw.to_s.strip
    return value if value.blank?
    return "+#{value.gsub(/[^\d]/, '')}" if value.start_with?("+")

    digits = value.gsub(/[^\d]/, "")
    case digits.length
    when 10 then "+1#{digits}"
    when 11 then digits.start_with?("1") ? "+#{digits}" : "+#{digits}"
    else digits.presence || value
    end
  end

  private

  def refresh_search_name
    self.search_name = "#{first_name} #{last_name} #{email}".downcase.strip
  end
end
