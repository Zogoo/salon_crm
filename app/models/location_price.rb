class LocationPrice < ApplicationRecord
  belongs_to :location
  belongs_to :service_variant

  validates :price_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :effective_from, presence: true
  validate  :no_overlapping_period

  scope :effective_on, ->(date) {
    where("effective_from <= ?", date)
      .where("effective_to IS NULL OR effective_to >= ?", date)
  }

  private

  # Invariant 5 (doc 02 §4). Was a Postgres EXCLUDE on daterange; on SQLite it
  # is this check (doc 08 §2).
  def no_overlapping_period
    clash = LocationPrice
              .where(location_id:, service_variant_id:)
              .where.not(id:)
              .where("effective_from <= ?", effective_to || Date.new(9999, 12, 31))
              .where("effective_to IS NULL OR effective_to >= ?", effective_from)
    errors.add(:effective_from, "overlaps an existing price period") if clash.exists?
  end
end
