# Doc 02 §3.2: several rows per weekday are allowed, which is how split hours
# (open, close for the afternoon, reopen) are expressed.
class LocationBusinessHour < ApplicationRecord
  belongs_to :location

  validates :day_of_week, inclusion: { in: 0..6 }
  validate :closes_after_opens

  scope :for_day, ->(dow) { where(day_of_week: dow).order(:opens_at) }

  private

  def closes_after_opens
    return if opens_at.blank? || closes_at.blank? || closes_at > opens_at
    errors.add(:closes_at, "must be after opening")
  end
end
