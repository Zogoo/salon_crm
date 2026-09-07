# Carries a denormalised copy of the parent's interval and status so the
# therapist-conflict query needs no join. Under Postgres this table held the
# exclusion constraint; on SQLite the equivalent check lives in
# Scheduling::BookAppointment (doc 08 §2).
class AppointmentStaff < ApplicationRecord
  self.table_name = "appointment_staff"

  belongs_to :appointment
  belongs_to :staff_profile

  validates :staff_profile_id, uniqueness: { scope: :appointment_id }

  scope :active, -> { where(status: Appointment::ACTIVE_STATUSES) }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }
end
