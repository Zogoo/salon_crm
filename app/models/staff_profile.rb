class StaffProfile < ApplicationRecord
  belongs_to :user
  belongs_to :location
  has_many :staff_qualifications, dependent: :destroy
  has_many :services, through: :staff_qualifications
  has_many :staff_session_rates, dependent: :destroy
  has_many :shifts, dependent: :destroy
  has_many :appointment_staff, dependent: :restrict_with_error
  has_many :appointments, through: :appointment_staff
  has_many :staff_requests, dependent: :destroy

  validates :employee_code, :display_name, presence: true
  validates :employee_code, uniqueness: true

  scope :active, -> { where(status: "active") }

  # BR-01: qualification is at service level, so every duration of a service
  # the therapist is certified in is covered.
  def qualified_for?(service_ids)
    Array(service_ids).uniq.all? do |sid|
      staff_qualifications.exists?(service_id: sid, active: true)
    end
  end

  # BR-35: the rate that applied on the service date, not today's rate.
  def rate_cents_for(duration_minutes, on:)
    staff_session_rates
      .where(duration_minutes:)
      .where("effective_from <= ?", on)
      .where("effective_to IS NULL OR effective_to >= ?", on)
      .order(effective_from: :desc).first&.rate_cents
  end
end
