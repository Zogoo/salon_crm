class User < ApplicationRecord
  # FRS §2. `front_desk` does not exist — Manager and front desk are one role.
  ROLES = %w[owner manager staff client].freeze

  has_secure_password
  has_one_attached :avatar

  belongs_to :location, optional: true          # required for manager (BR-02)
  has_one :staff_profile, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  STATUSES = %w[invited active suspended disabled].freeze

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validate :manager_must_have_one_location
  validate :acceptable_avatar

  ROLES.each { |r| define_method("#{r}?") { role == r } }

  # BR-02: offboarding disables the login. A terminated therapist must not keep
  # reach into schedules, earnings or the care notes of clients they saw.
  def active_for_authentication? = status == "active"

  # --- second factor (doc 05 §3) ---

  def otp_enabled? = otp_enabled_at.present? && otp_secret.present?

  # The Owner holds every location, every rate and every money report, so the
  # spec requires a second factor on that account specifically.
  def otp_required? = owner?

  def verify_otp(code)
    return false unless otp_enabled? && code.present?

    # drift_behind allows the previous 30s window, so a code entered as it
    # rolls over is still accepted.
    ROTP::TOTP.new(otp_secret).verify(code.to_s.strip, drift_behind: 30).present?
  end

  # --- password reset ---

  # Stored as a digest: a leaked row must not be replayable against the reset
  # endpoint, exactly as a password must not be.
  def issue_password_reset!
    raw = SecureRandom.urlsafe_base64(32)
    update!(password_reset_token_digest: self.class.digest_token(raw),
            password_reset_sent_at: Time.current)
    raw
  end

  def password_reset_valid?(window: 2.hours)
    password_reset_sent_at.present? && password_reset_sent_at > window.ago
  end

  def clear_password_reset! = update!(password_reset_token_digest: nil, password_reset_sent_at: nil)

  def self.digest_token(raw) = Digest::SHA256.hexdigest(raw.to_s)

  def self.find_by_reset_token(raw)
    return nil if raw.blank?
    find_by(password_reset_token_digest: digest_token(raw))
  end

  # BR-01: only the Owner sees all four locations. A Manager is pinned to one
  # and cannot switch; Staff are scoped to their own records.
  def accessible_location_ids
    return Location.pluck(:id) if owner?
    return [ location_id ].compact if manager?
    [ staff_profile&.location_id ].compact
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
