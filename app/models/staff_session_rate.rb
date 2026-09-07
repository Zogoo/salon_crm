class StaffSessionRate < ApplicationRecord
  belongs_to :staff_profile

  validates :duration_minutes, inclusion: { in: ServiceVariant::LADDER }
  validates :rate_cents, numericality: { greater_than_or_equal_to: 0 }
  validate  :no_overlapping_period

  private

  # Invariant 4 (doc 02 §4) — was a Postgres EXCLUDE on daterange.
  def no_overlapping_period
    clash = StaffSessionRate
              .where(staff_profile_id:, duration_minutes:)
              .where.not(id:)
              .where("effective_from <= ?", effective_to || Date.new(9999, 12, 31))
              .where("effective_to IS NULL OR effective_to >= ?", effective_from)
    errors.add(:effective_from, "overlaps an existing rate period") if clash.exists?
  end
end
