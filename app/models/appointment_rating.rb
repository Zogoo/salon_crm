# FRS §11.2 / BR-45. One rating per appointment, always tied to the therapist.
class AppointmentRating < ApplicationRecord
  CHANNELS = %w[kiosk sms_link].freeze

  belongs_to :appointment
  belongs_to :staff_profile

  validates :score, inclusion: { in: 1..10 }
  validates :channel, inclusion: { in: CHANNELS }
  validates :appointment_id, uniqueness: true

  # BR-45a: below the location threshold, not at it.
  def low?(threshold) = score < threshold
end
