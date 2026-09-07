class MembershipCreditTransaction < ApplicationRecord
  KINDS = %w[grant redeem expire adjust].freeze

  belongs_to :membership
  belongs_to :appointment, optional: true
  belongs_to :membership_cycle, optional: true
  belongs_to :performed_by_user, class_name: "User", optional: true
  belongs_to :cross_location_approved_by_user, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
end
