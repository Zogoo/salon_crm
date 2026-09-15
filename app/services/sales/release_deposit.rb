module Sales
  # What happens to a held deposit when the visit does not go ahead.
  #
  # * Cancelled in time (or the therapist request was rejected, or the desk
  #   undoes it): the whole deposit goes back to the client.
  # * Late cancellation or no-show: the BR-19 fee is taken from the deposit —
  #   paying the fee order with it — and whatever is left goes back.
  #
  # The refund itself happens at the terminal or the drawer; this records it.
  class ReleaseDeposit < ApplicationService
    def initialize(appointment:, actor: nil, fee_order: nil, reason: nil)
      @appt = appointment
      @actor = actor
      @fee_order = fee_order
      @reason = reason
    end

    def call
      deposit = Deposit.held.find_by(appointment_id: @appt.id)
      return nil unless deposit

      ImmediateTransaction.call do
        fee_taken = take_fee!(deposit)
        refunded = deposit.amount_cents - fee_taken
        deposit.update!(
          status: fee_taken.positive? ? "forfeited" : "refunded",
          fee_cents: fee_taken, refunded_cents: refunded,
          applied_order: fee_taken.positive? ? @fee_order : nil,
          resolved_at: Time.current, resolved_by_user: @actor,
          note: [ deposit.note, @reason ].compact.join(" · ").presence
        )
        AuditLog.record!(auditable: deposit, action: "deposit.#{deposit.status}", actor: @actor,
                         changes: { appointment: @appt.reference, fee_cents: fee_taken,
                                    refunded_cents: refunded })
        deposit
      end
    end

    private

    def take_fee!(deposit)
      return 0 unless @fee_order

      @fee_order.reload.recalculate!
      amount = [ deposit.amount_cents, @fee_order.outstanding_cents ].min
      return 0 unless amount.positive?

      Payment.create!(
        order: @fee_order, method: deposit.method, processing: "deposit",
        amount_cents: amount, reference: "Deposit ##{deposit.id}",
        received_at: deposit.received_at, received_by_user: deposit.received_by_user
      )
      SettleOrder.call(order: @fee_order, actor: @actor) unless @fee_order.reload.outstanding_cents.positive?
      amount
    end
  end
end
