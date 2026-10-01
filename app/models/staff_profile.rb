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
  has_many :earning_lines, dependent: :restrict_with_error
  has_many :earning_statements, dependent: :destroy
  has_many :tip_allocations, dependent: :restrict_with_error
  has_many :care_notes, dependent: :restrict_with_error
  has_many :appointment_ratings, dependent: :nullify
  has_many :staff_monthly_rates, dependent: :destroy
  has_many :staff_working_hours, dependent: :destroy

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
  def manager? = engagement_type == "manager_flat"

  # Addendum §8: the usual hours set for the weekday of `date`, if any. `nil`
  # means "not set" and places no limit; a row marked off means not working.
  def working_hours_on(date)
    staff_working_hours.to_a.find { |row| row.weekday == date.wday }
  end

  # True when `from`–`to` sits inside the usual hours for that day, or no hours
  # are set. One rule for search, booking and assignment, so none can disagree.
  def within_working_hours?(from, to, tz)
    date = from.in_time_zone(tz).to_date
    row = working_hours_on(date)
    return true unless row

    window = row.window_on(date, tz)
    window.present? && window.first <= from && window.last >= to
  end

  def rate_cents_for(duration_minutes, on:)
    staff_session_rates
      .where(duration_minutes:)
      .where("effective_from <= ?", on)
      .where("effective_to IS NULL OR effective_to >= ?", on)
      .order(effective_from: :desc).first&.rate_cents
  end
end
