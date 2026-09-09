# Doc 02 §3.2: time-bounded unavailability for one room — deep clean, repair,
# private event. Distinct from rooms.status = 'maintenance', which takes a room
# out of service indefinitely. Blocks participate in the availability search
# exactly like appointments.
class RoomBlock < ApplicationRecord
  belongs_to :room
  belongs_to :created_by_user, class_name: "User", optional: true

  validates :starts_at, :ends_at, presence: true
  validate :ends_after_starts

  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at
    errors.add(:ends_at, "must be after the start")
  end
end
