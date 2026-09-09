module Workforce
  # FRS §4 / BR-35: the six-rung pay ladder, effective-dated.
  #
  # A rate is never edited in place. Earnings are calculated from the rate that
  # applied on the *service date*, so changing an existing row would silently
  # restate pay for work already done. Instead the open period is closed the day
  # before the new one starts and six fresh rows are written.
  #
  # All six rungs must arrive together: a ladder with a gap is a therapist whose
  # pay fails on some bookings and nobody notices until payroll.
  class SetSessionRates < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, rates:, effective_from:, actor: nil, note: nil)
      @profile = staff_profile
      @rates = Array(rates)
      @effective_from = effective_from.to_date
      @actor = actor
      @note = note
    end

    def call
      assert_complete_ladder!

      ImmediateTransaction.call do
        ::EffectiveDating.close_open_periods!(@profile.staff_session_rates, @effective_from)
        # create!, not insert_all: the no-overlap validation on the model is
        # what replaces the Postgres EXCLUDE constraint (doc 02 §4). Skipping
        # validations here would quietly remove the guarantee.
        @rates.each { |r| create_row!(r) }
        AuditLog.record!(auditable: @profile, action: "staff.session_rates.set", actor: @actor,
                         changes: { effective_from: @effective_from, note: @note })
        @profile.staff_session_rates.reload
      end
    end

    private

    def assert_complete_ladder!
      given = @rates.map { |r| r[:duration_minutes].to_i }.sort
      raise Invalid, "ladder_incomplete" unless given == ServiceVariant::LADDER.sort
      raise Invalid, "negative_rate" if @rates.any? { |r| r[:rate_cents].to_i.negative? }
    end

    def create_row!(rate)
      @profile.staff_session_rates.create!(
        duration_minutes: rate[:duration_minutes].to_i,
        rate_cents: rate[:rate_cents].to_i,
        effective_from: @effective_from, effective_to: nil, note: @note
      )
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, "rate_overlap: #{e.record.errors.full_messages.join(', ')}"
    end
  end
end
