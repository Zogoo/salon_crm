class StaffRequest < ApplicationRecord
  KINDS    = %w[shift_change location_change].freeze
  STATUSES = %w[submitted approved rejected withdrawn].freeze

  belongs_to :staff_profile
  belongs_to :shift, optional: true
  belongs_to :reviewed_by_user, class_name: "User", optional: true

  # Stored as text: the SQLite schema dumper cannot round-trip a json column.
  serialize :requested_payload, coder: JSON, type: Hash

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validate  :location_change_reviewed_only_by_owner

  scope :pending, -> { where(status: "submitted") }

  private

  # BR-06 — the one approval the Owner explicitly withheld from Managers.
  # Enforced here as well as in the policy layer (doc 04 §4.4).
  def location_change_reviewed_only_by_owner
    return unless kind == "location_change"
    return if reviewer_role.blank? || reviewer_role == "owner"

    errors.add(:base, "only the Owner can approve a location change")
  end
end
