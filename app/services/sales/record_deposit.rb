module Sales
  # Records a deposit taken in the salon before the visit — over the phone by
  # card, or in cash or Zelle. Release 1 records money, it does not move it
  # (doc 08 §1), so this is the desk typing in what already happened.
  #
  # The deposit is held for the client until checkout (a liability, BR-48).
  class RecordDeposit < ApplicationService
    Invalid = Class.new(StandardError)

    OPEN = %w[pending_approval scheduled checked_in].freeze

    def initialize(appointment:, amount_cents:, method:, actor:, reference: nil, note: nil)
      @appt = appointment
      @amount = amount_cents.to_i
      @method = method.to_s
      @actor = actor
      @reference = reference.presence
      @note = note.presence
    end

    def call
      raise Invalid, "amount_must_be_positive" unless @amount.positive?
      raise Invalid, "unknown_payment_method" unless Payment::METHODS.include?(@method)
      raise Invalid, "cannot_take_deposit_#{@appt.status}" unless OPEN.include?(@appt.status)

      ImmediateTransaction.call do
        raise Invalid, "deposit_already_recorded" if Deposit.exists?(appointment_id: @appt.id)
        raise Invalid, "deposit_exceeds_price" if @amount > @appt.reload.total_price_cents

        deposit = Deposit.create!(
          appointment: @appt, client: @appt.client, location: @appt.location,
          amount_cents: @amount, method: @method, reference: @reference, note: @note,
          received_at: Time.current, received_by_user: @actor
        )
        AuditLog.record!(auditable: deposit, action: "deposit.recorded", actor: @actor,
                         changes: { appointment: @appt.reference, amount_cents: @amount,
                                    method: @method })
        deposit
      end
    end
  end
end
