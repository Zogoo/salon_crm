module Sales
  # Addendum §2: a completed, paid visit can be corrected afterwards — the
  # therapist, the tip, the transaction fee, the deposit and how it was paid
  # (including a split). Every figure the reports and earnings show is derived
  # from these rows, so fixing the rows is what makes the reports correct.
  #
  # Money is never edited in place (BR-23): the payments taken are voided with
  # the reason and the corrected ones recorded, so the before and after both
  # stay on the record. The visit keeps its date and its closing time.
  class CorrectVisit < ApplicationService
    Invalid = Class.new(StandardError)
    Conflict = Class.new(StandardError)

    # payments: [{ method:, amount_cents:, code: }] — what the client paid
    # besides the deposit, one or two parts (Addendum §1).
    def initialize(appointment:, actor:, reason:, payments:, staff_profile_ids: nil,
                   tip_cents: nil, transaction_fee_cents: nil, deposit: nil)
      @appt = appointment
      @actor = actor
      @reason = reason.to_s.strip
      @payments = Array(payments).map { |p| p.to_h.symbolize_keys }
      @staff_ids = staff_profile_ids&.map(&:to_i)&.uniq
      @tip = tip_cents&.to_i
      @fee = transaction_fee_cents&.to_i
      @deposit = deposit&.to_h&.symbolize_keys
    end

    def call
      raise Invalid, "reason_required" if @reason.blank?
      raise Invalid, "too_many_parts" if @payments.size > TakePayments::MAX_PARTS
      raise Invalid, "tip_invalid" if @tip&.negative?
      raise Invalid, "fee_invalid" if @fee&.negative?
      @payments.each do |p|
        raise Invalid, "unknown_payment_method" unless TakePayments.valid_method?(p[:method])
        raise Invalid, "amount_must_be_positive" unless p[:amount_cents].to_i.positive?
      end

      ImmediateTransaction.call do
        order = VisitCorrection.assert_correctable!(@appt)
        before = VisitCorrection.money_summary(order)
        void_reason = "Visit corrected: #{@reason}"

        VisitCorrection.clear_generated_earnings!(@appt)
        VisitCorrection.void_money!(order, actor: @actor, reason: void_reason)
        staff_changed = @staff_ids.present? && @staff_ids.sort != @appt.staff_profiles.ids.sort
        reassign_staff! if staff_changed
        # A new therapist takes the tip with them; a new tip is split afresh.
        if staff_changed || !@tip.nil?
          order.appointment.reload
          AllocateTips.call(order:, amount_cents: @tip.nil? ? order.tip_cents : @tip, actor: @actor)
        end
        order.update!(transaction_fee_cents: @fee) unless @fee.nil?
        correct_deposit!(order)
        order.recalculate!

        due = order.outstanding_cents
        given = @payments.sum { |p| p[:amount_cents].to_i }
        raise Invalid, "split_total_mismatch:#{due}" unless given == due

        @payments.each { |part| TakePayments.record!(order, part, @actor) }
        raise Invalid, "split_total_mismatch:#{due}" unless order.reload.outstanding_cents.zero?

        Earnings::GenerateForAppointment.call(appointment: @appt.reload)
        Earnings::GenerateForTip.call(order: order.reload)
        VisitCorrection.rebuild_statements!(@appt)

        AuditLog.record!(auditable: @appt, action: "appointment.visit_corrected", actor: @actor,
                         changes: { reason: @reason, from: before, to: VisitCorrection.money_summary(order) })
        @appt.reload
      end
    end

    private

    # The visit happened, so the question is only who did it: qualified, the
    # right number of them, and not booked elsewhere at the same time.
    def reassign_staff!
      shape = Scheduling::AppointmentShape.call(
        variants: @appt.appointment_items.includes(:service_variant).map(&:service_variant)
      )
      raise Invalid, "wrong_therapist_count" unless @staff_ids.size == shape.therapist_count

      staff = StaffProfile.where(id: @staff_ids, location_id: @appt.location_id).to_a
      raise Invalid, "therapist_not_found" unless staff.size == @staff_ids.size
      staff.each do |member|
        raise Invalid, "therapist_not_qualified" unless member.qualified_for?(shape.service_ids)

        clash = AppointmentStaff.active.overlapping(@appt.starts_at, @appt.ends_at)
                                .where(staff_profile_id: member.id)
                                .where.not(appointment_id: @appt.id).exists?
        raise Conflict, "therapist_unavailable" if clash
      end

      @appt.appointment_staff.delete_all
      staff.sort_by { |m| @staff_ids.index(m.id) }.each_with_index do |member, index|
        @appt.appointment_staff.create!(
          staff_profile: member, role: index.zero? ? "primary" : "secondary",
          starts_at: @appt.starts_at, ends_at: @appt.ends_at, status: @appt.status
        )
      end
      @appt.update!(staff_assignment_confirmed: true)
      # Service lines are credited to the therapist who delivered them.
      @appt.order.order_line_items.where(purchasable_type: "ServiceVariant")
           .update_all(staff_profile_id: staff.first.id)
    end

    # The deposit was turned into a payment when the visit settled. A corrected
    # deposit is re-entered the same way: the deposit row carries the truth,
    # and its payment is recorded again to match.
    def correct_deposit!(order)
      deposit = Deposit.find_by(appointment_id: @appt.id, status: "applied")
      return unless deposit

      if @deposit
        amount = @deposit[:amount_cents].to_i
        method = @deposit[:method].presence || deposit.method
        raise Invalid, "deposit_invalid" unless amount.positive? && Payment::METHODS.include?(method)

        deposit.update!(amount_cents: amount, method:)
      end
      Payment.create!(
        order:, method: deposit.method, processing: "deposit",
        amount_cents: deposit.amount_cents, reference: "Deposit ##{deposit.id}",
        received_at: deposit.received_at, received_by_user: deposit.received_by_user
      )
    end
  end
end
