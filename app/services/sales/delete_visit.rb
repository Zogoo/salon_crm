module Sales
  # Addendum §2: a completed visit entered by mistake can be deleted. Nothing is
  # erased: the order is voided, its payments are voided, gift card money goes
  # back on the card, a membership credit goes back to the member, and the
  # therapist's pay for it is removed. The appointment leaves the schedule and
  # every report, and the audit log keeps who did it and why.
  #
  # If the client really did pay, that money has to be returned to them — this
  # only corrects the records.
  class DeleteVisit < ApplicationService
    Invalid = VisitCorrection::Invalid

    def initialize(appointment:, actor:, reason:)
      @appt = appointment
      @actor = actor
      @reason = reason.to_s.strip
    end

    def call
      raise Invalid, "reason_required" if @reason.blank?

      ImmediateTransaction.call do
        order = VisitCorrection.assert_correctable!(@appt)
        before = VisitCorrection.money_summary(order)
        void_reason = "Visit deleted: #{@reason}"

        VisitCorrection.clear_generated_earnings!(@appt)
        VisitCorrection.void_money!(order, actor: @actor, reason: void_reason)
        return_membership_credit!(order)
        Deposit.where(appointment_id: @appt.id, status: "applied").find_each do |deposit|
          deposit.update!(status: "refunded", refunded_cents: deposit.amount_cents,
                          resolved_at: Time.current, resolved_by_user: @actor)
        end
        order.update!(status: "voided")

        from = @appt.status
        @appt.update!(status: "deleted")
        @appt.appointment_staff.update_all(status: "deleted")
        AppointmentStatusEvent.create!(appointment: @appt, from_status: from, to_status: "deleted",
                                       actor_user: @actor, occurred_at: Time.current, reason: @reason)
        VisitCorrection.rebuild_statements!(@appt)
        AuditLog.record!(auditable: @appt, action: "appointment.visit_deleted", actor: @actor,
                         changes: { reason: @reason, removed: before })
        @appt
      end
    end

    private

    def return_membership_credit!(order)
      return unless order.order_discounts.exists?(kind: "membership_upgrade_credit")

      membership = order.client&.membership
      return unless membership

      membership = Membership.lock.find(membership.id)
      balance = [ membership.credits_balance + 1, Membership::CREDIT_CAP ].min
      MembershipCreditTransaction.create!(
        membership:, kind: "adjust", amount: balance - membership.credits_balance,
        balance_after: balance, appointment: @appt, performed_by_user: @actor,
        occurred_at: Time.current, note: "Visit deleted: #{@reason}"
      )
      membership.update!(credits_balance: balance)
    end
  end
end
