# Addendum §8: a therapist's usual hours for one weekday. Advisory about the
# future only — changing them never touches an appointment already booked.
class StaffWorkingHour < ApplicationRecord
  HHMM = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :staff_profile

  validates :weekday, inclusion: { in: 0..6 }, uniqueness: { scope: :staff_profile_id }
  validates :starts_at, :ends_at, presence: true, format: { with: HHMM }, unless: :off?
  validate  :ends_after_starts, unless: :off?

  # The hours as real times on `date`, in the zone the location keeps.
  def window_on(date, tz)
    return nil if off?

    [ tz.parse("#{date} #{starts_at}"), tz.parse("#{date} #{ends_at}") ]
  end

  private

  # "HH:MM" strings compare correctly as text, so no parsing is needed.
  def ends_after_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at

    errors.add(:ends_at, "must be after the start")
  end
end
