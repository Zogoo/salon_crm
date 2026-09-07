module Memberships
  # FRS §23. $80/month, one 60-minute massage per cycle. Release 1 bills by
  # hand: recording the monthly payment is what grants the credit (doc 08 §1).
  class Enrol < ApplicationService
    Invalid = Class.new(StandardError)
    PRICE_CENTS = 8000

    def initialize(client:, location:, actor: nil, default_service_variant_id: nil, now: Time.current)
      @client = client
      @location = location
      @actor = actor
      @variant_id = default_service_variant_id
      @now = now
    end

    def call
      raise Invalid, "already_a_member" if Membership.active.exists?(client_id: @client.id)

      ImmediateTransaction.call do
        membership = Membership.create!(
          client: @client, location: @location, status: "active",
          price_cents: PRICE_CENTS,
          default_service_variant_id: @variant_id,
          enrolled_at: @now,
          current_period_start: @now,
          current_period_end: @now + 1.month,
          credits_balance: 0
        )
        AuditLog.record!(auditable: membership, action: "membership.enrolled", actor: @actor,
                         changes: { client: @client.full_name, location: @location.code })
        membership
      end
    end
  end
end
