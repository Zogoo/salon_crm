class StaffMonthlyRate < ApplicationRecord
  belongs_to :staff_profile
  belongs_to :created_by_user, class_name: "User", optional: true

  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
  validate  :no_overlapping_period

  private

  def no_overlapping_period
    clash = StaffMonthlyRate.where(staff_profile_id:).where.not(id:)
                            .where("effective_from <= ?", effective_to || Date.new(9999, 12, 31))
                            .where("effective_to IS NULL OR effective_to >= ?", effective_from)
    errors.add(:effective_from, "overlaps an existing rate period") if clash.exists?
  end
end
