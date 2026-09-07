module Memberships
  # BR-40: cancelling needs 15 days' notice. Inside that window the cancellation
  # takes effect after the *following* period — the next charge still happens.
  class RequestCancellation < ApplicationService
    def initialize(membership:, actor: nil, now: Time.current)
      @membership = membership
      @actor = actor
      @now = now
    end

    def call
      effective = @membership.cancellation_effective_for(@now)

      ImmediateTransaction.call do
        @membership.update!(
          status: "pending_cancellation",
          cancellation_requested_at: @now,
          cancellation_effective_at: effective
        )
        AuditLog.record!(auditable: @membership, action: "membership.cancellation_requested",
                         actor: @actor, changes: { effective_at: effective.to_s })
        @membership
      end
    end
  end
end
