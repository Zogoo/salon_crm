class User < ApplicationRecord
  has_secure_password
  has_one_attached :avatar

  has_many :notes, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validate :acceptable_avatar

  normalizes :email, with: ->(e) { e.strip.downcase }

  private

  def acceptable_avatar
    return unless avatar.attached?

    if avatar.blob.byte_size > 5.megabytes
      errors.add(:avatar, "must be smaller than 5MB")
    end

    allowed = %w[image/jpeg image/png image/webp]
    errors.add(:avatar, "must be a JPEG, PNG, or WEBP image") unless allowed.include?(avatar.blob.content_type)
  end
end
