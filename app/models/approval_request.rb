class ApprovalRequest < ApplicationRecord
  # BR-15a: 45 minutes is the backstop; 15 is the review target.
  AUTO_APPROVE_AFTER = 45.minutes
  REVIEW_TARGET      = 15.minutes

  belongs_to :appointment
  belongs_to :requested_staff_profile, class_name: "StaffProfile"
  belongs_to :requested_by_user, class_name: "User", optional: true
  belongs_to :reviewed_by_user, class_name: "User", optional: true

  scope :pending, -> { where(status: "pending") }

  def pending_for_minutes = ((Time.current - created_at) / 60).floor
  def auto_approves_at    = created_at + AUTO_APPROVE_AFTER
  def past_review_target? = pending_for_minutes > (REVIEW_TARGET / 60)
end
