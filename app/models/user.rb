class User < ApplicationRecord
  # FRS §2. `front_desk` does not exist — Manager and front desk are one role.
  ROLES = %w[owner manager staff client].freeze

  has_secure_password
  has_one_attached :avatar

  has_many :notes, dependent: :destroy
  belongs_to :location, optional: true          # required for manager (BR-02)
  has_one :staff_profile, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :role, inclusion: { in: ROLES }
  validate :manager_must_have_one_location
  validate :acceptable_avatar

  ROLES.each { |r| define_method("#{r}?") { role == r } }

  # BR-01: only the Owner sees all four locations. A Manager is pinned to one
  # and cannot switch; Staff are scoped to their own records.
  def accessible_location_ids
    return Location.pluck(:id) if owner?
    return [location_id].compact if manager?
    [staff_profile&.location_id].compact
  end

  def can_access_location?(id) = owner? || accessible_location_ids.include?(id.to_i)

  # BR-14: staff never create appointments, not even for themselves.
  def can_create_appointments? = owner? || manager?
  def can_view_money?          = owner?
  def can_manage_staff?        = owner?

  normalizes :email, with: ->(e) { e.strip.downcase }

  private

  def manager_must_have_one_location
    errors.add(:location, "is required for a manager") if manager? && location_id.blank?
  end

  def acceptable_avatar
    return unless avatar.attached?

    if avatar.blob.byte_size > 5.megabytes
      errors.add(:avatar, "must be smaller than 5MB")
    end

    allowed = %w[image/jpeg image/png image/webp]
    errors.add(:avatar, "must be a JPEG, PNG, or WEBP image") unless allowed.include?(avatar.blob.content_type)
  end
end
