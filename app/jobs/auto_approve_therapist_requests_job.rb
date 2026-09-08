# BR-15a: a request pending more than 45 minutes is approved automatically —
# but only after re-checking that the requested therapist still has a covering
# shift and no conflict. 45 minutes is the backstop; the review target is 15.
class AutoApproveTherapistRequestsJob < ApplicationJob
  def perform(now: Time.current)
    cutoff = now - ApprovalRequest::AUTO_APPROVE_AFTER
    ApprovalRequest.pending.where(created_at: ..cutoff).find_each do |request|
      Scheduling::ApproveTherapistRequest.call(
        request:, actor: nil, decision: :approve, now:
      )
    end
  end
end
