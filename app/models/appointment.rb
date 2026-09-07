class Appointment < ApplicationRecord
  # Statuses that occupy a room and a therapist. A row leaves this set and the
  # resources are free again (BR-21) — the same predicate the Postgres partial
  # exclusion constraints used.
  ACTIVE_STATUSES = %w[pending_approval scheduled checked_in in_progress completed].freeze
  STATUSES = (ACTIVE_STATUSES + %w[cancelled late_cancelled no_show]).freeze

  belongs_to :client
  belongs_to :location
  belongs_to :room
  belongs_to :created_by_user, class_name: "User", optional: true
  belongs_to :requested_staff_profile, class_name: "StaffProfile", optional: true
  belongs_to :rescheduled_from, class_name: "Appointment", optional: true

  has_many :appointment_staff, dependent: :destroy
  has_many :staff_profiles, through: :appointment_staff
  has_many :appointment_items, dependent: :destroy
  has_many :appointment_participants, dependent: :destroy
  has_many :appointment_status_events, dependent: :destroy
  has_one  :approval_request, dependent: :destroy

  validates :reference, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validate  :ends_after_starts

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }
  scope :on_date, ->(location, date) {
    w = location.open_window(date)
    where(location_id: location.id).where(starts_at: w.first.beginning_of_day..w.first.end_of_day)
  }

  def active? = ACTIVE_STATUSES.include?(status)
  def duration_minutes = ((service_ends_at - starts_at) / 60).round

  def self.generate_reference
    "APT-#{Time.current.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
  end

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank?
    errors.add(:ends_at, "must be after the start") if ends_at <= starts_at
  end
end
