module Workforce
  # Addendum §8: saves a therapist's usual week in one go. Sent as the whole
  # week, so a day cleared on screen is simply absent here.
  #
  # Only the working-hours rows change. Appointments already booked are never
  # moved, cancelled or re-priced by this — the hours shape what is offered
  # from now on, nothing else.
  class SetWorkingHours < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, days:, actor:)
      @staff = staff_profile
      @days = Array(days).map { |d| d.to_h.symbolize_keys }
      @actor = actor
    end

    def call
      weekdays = @days.map { |d| d[:weekday].to_i }
      raise Invalid, "each weekday may appear once" unless weekdays.uniq.size == weekdays.size

      ImmediateTransaction.call do
        before = snapshot
        @staff.staff_working_hours.delete_all
        @days.each do |day|
          off = ActiveModel::Type::Boolean.new.cast(day[:off]) || false
          row = @staff.staff_working_hours.build(
            weekday: day[:weekday].to_i, off:,
            starts_at: off ? nil : day[:starts_at].presence,
            ends_at: off ? nil : day[:ends_at].presence
          )
          raise Invalid, "#{Date::DAYNAMES[row.weekday.to_i] || 'A day'}: #{row.errors.full_messages.to_sentence.downcase}" unless row.save
        end
        AuditLog.record!(auditable: @staff, action: "staff.working_hours_updated", actor: @actor,
                         changes: { from: before, to: snapshot })
        @staff.staff_working_hours.reload
      end
    end

    private

    def snapshot
      @staff.staff_working_hours.reload.order(:weekday)
            .map { |r| [ r.weekday, r.off? ? "off" : "#{r.starts_at}-#{r.ends_at}" ] }.to_h
    end
  end
end
