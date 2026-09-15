# BR-15a: a request pending more than 45 minutes is approved automatically —
# but only after re-checking that the requested therapist still has a covering
# shift and no conflict. 45 minutes is the backstop; the review target is 15.
#
# One bad record must never stop the rest: each request is handled on its own,
# and a request whose appointment is no longer waiting is closed, not retried.
class AutoApproveTherapistRequestsJob < ApplicationJob
  def perform(now: Time.current)
    cutoff = now - ApprovalRequest::AUTO_APPROVE_AFTER
    ApprovalRequest.pending.where(created_at: ..cutoff).includes(:appointment).find_each do |request|
      unless request.appointment&.status == "pending_approval"
        request.update!(status: "withdrawn", reviewed_at: now)
        next
      end

      Scheduling::ApproveTherapistRequest.call(request:, actor: nil, decision: :approve, now:)
    rescue StandardError => e
      Rails.logger.error("[auto-approve] request #{request.id}: #{e.class}: #{e.message}")
    end
  end
end
