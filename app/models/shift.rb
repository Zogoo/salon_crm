class Shift < ApplicationRecord
  belongs_to :staff_profile
  belongs_to :location
  has_many :shift_breaks, dependent: :destroy

  validates :starts_at, :ends_at, :work_date, presence: true
  validate  :ends_after_starts
  validate  :no_overlapping_shift

  scope :published, -> { where(status: "published") }
  scope :overlapping, ->(from, to) { where("starts_at < ? AND ends_at > ?", to, from) }

  def covers?(from, to) = starts_at <= from && ends_at >= to

  private

  def ends_after_starts
    return if starts_at.blank? || ends_at.blank? || ends_at > starts_at
    errors.add(:ends_at, "must be after the start")
  end

  # BR-04 / invariant 3. Company-wide: a therapist cannot be on shift at two
  # locations at once. Was a Postgres EXCLUDE; on SQLite it is this check.
  def no_overlapping_shift
    return if starts_at.blank? || ends_at.blank? || status != "published"

    clash = Shift.published
                 .where(staff_profile_id:)
                 .where.not(id:)
                 .overlapping(starts_at, ends_at)
    errors.add(:base, "overlaps another published shift for this therapist") if clash.exists?
  end
end
