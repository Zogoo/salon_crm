module Sales
  # What correcting and deleting a completed visit have in common: taking back
  # the money recorded against it and the pay it generated, without erasing any
  # of it. Payments are voided (BR-23 — never edited), gift card redemptions are
  # credited back to the card, and the therapist's generated lines are removed
  # so they can be derived again. Nothing here is exposed on its own.
  module VisitCorrection
    Invalid = Class.new(StandardError)

    module_function

    def assert_correctable!(appointment)
      order = appointment.order
      raise Invalid, "visit_not_completed" unless appointment.status == "completed"
      raise Invalid, "visit_not_settled" unless order&.status == "paid"
      raise Invalid, "visit_has_refunds" if order.refunds.exists?
      raise Invalid, "period_locked" if period_locked?(appointment)

      order
    end

    # BR-37: a locked pay period is read-only, and editing a visit changes pay.
    def period_locked?(appointment)
      date = appointment.starts_at.in_time_zone(appointment.location.tz).to_date
      starts_on, ends_on = EarningPeriod.semi_monthly_bounds(date)
      EarningPeriod.locked.exists?(starts_on:, ends_on:)
    end

    def void_money!(order, actor:, reason:, keep_deposit: false)
      order.payments.captured.each do |payment|
        next if keep_deposit && payment.processing == "deposit"

        payment.update!(status: "voided", voided_by_user: actor, voided_at: Time.current,
                        void_reason: reason)
      end
      order.live_redemptions.each do |redeemed_card, cents|
        card = GiftCard.lock.find(redeemed_card.id)
        balance = card.current_balance_cents + cents
        GiftCardTransaction.create!(
          gift_card: card, kind: "refund", amount_cents: cents,
          balance_after_cents: balance, order:, appointment: order.appointment,
          performed_by_user: actor, location: order.location, occurred_at: Time.current
        )
        card.update!(current_balance_cents: balance,
                     status: card.status == "depleted" ? "active" : card.status)
      end
    end

    # Session and tip lines are derived from the visit; manual lines were
    # entered by a person and stay.
    def clear_generated_earnings!(appointment)
      EarningLine.where(appointment_id: appointment.id, source: %w[session tip]).delete_all
    end

    def rebuild_statements!(appointment)
      date = appointment.starts_at.in_time_zone(appointment.location.tz).to_date
      starts_on, ends_on = EarningPeriod.semi_monthly_bounds(date)
      period = EarningPeriod.find_by(starts_on:, ends_on:)
      Earnings::BuildStatements.call(period:) if period && !period.locked?
    end

    def money_summary(order)
      order.reload
      {
        total_cents: order.total_cents, tip_cents: order.tip_cents,
        transaction_fee_cents: order.transaction_fee_cents,
        staff: order.appointment&.staff_profiles&.map(&:display_name),
        payments: order.payments.captured.map { |p| [ p.method, p.amount_cents ] },
        gift_cards: order.live_redemptions.map { |card, cents| [ card.code, cents ] }
      }
    end
  end
end
