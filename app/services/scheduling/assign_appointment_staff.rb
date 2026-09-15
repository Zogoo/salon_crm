module Scheduling
  # Confirms the operational therapist reservation made for a no-preference
  # booking, or replaces it with another eligible team. Keeping a provisional
  # reservation until this happens preserves the no-double-booking guarantee.
  class AssignAppointmentStaff < ApplicationService
    Invalid = Class.new(StandardError)
    Conflict = Class.new(StandardError)

    EDITABLE = %w[scheduled checked_in].freeze

    def initialize(appointment:, staff_profile_ids:, actor: nil)
      @appointment = appointment
      @staff_ids = Array(staff_profile_ids).compact.map(&:to_i).uniq
      @actor = actor
    end

    def call
      raise Invalid, "cannot_assign_#{@appointment.status}" unless EDITABLE.include?(@appointment.status)

      shape = AppointmentShape.call(
        variants: @appointment.appointment_items.includes(:service_variant).map(&:service_variant)
      )
      raise Invalid, "wrong_therapist_count" unless @staff_ids.size == shape.therapist_count

      ImmediateTransaction.call do
        staff = StaffProfile.active.where(id: @staff_ids, location_id: @appointment.location_id).to_a
        raise Invalid, "therapist_not_found" unless staff.size == @staff_ids.size

        staff.each { |member| validate!(member, shape) }
        previous_ids = @appointment.staff_profiles.ids
        @appointment.appointment_staff.delete_all
        staff.each_with_index do |member, index|
          @appointment.appointment_staff.create!(
            staff_profile: member,
            role: index.zero? ? "primary" : "secondary",
            starts_at: @appointment.starts_at,
            ends_at: @appointment.ends_at,
            status: @appointment.status
          )
        end
        @appointment.update!(staff_assignment_confirmed: true)
        AuditLog.record!(
          auditable: @appointment, action: "appointment.staff_assigned", actor: @actor,
          changes: { staff_profile_ids: [ previous_ids, @staff_ids ] }
        )
        Sales::SyncOrder.call(appointment: @appointment.reload)
        @appointment.reload
      end
    end

    private

    def validate!(member, shape)
      raise Invalid, "therapist_not_qualified" unless member.qualified_for?(shape.service_ids)

      shift = Shift.published
                   .where(staff_profile: member, location: @appointment.location)
                   .overlapping(@appointment.starts_at, @appointment.ends_at)
                   .includes(:shift_breaks).find { |row| row.covers?(@appointment.starts_at, @appointment.ends_at) }
      raise Conflict, "therapist_not_on_shift" unless shift
      if shift.shift_breaks.any? { |row| row.starts_at < @appointment.ends_at && row.ends_at > @appointment.starts_at }
        raise Conflict, "therapist_on_break"
      end

      clash = AppointmentStaff.active
                              .overlapping(@appointment.starts_at, @appointment.ends_at)
                              .where(staff_profile_id: member.id)
                              .where.not(appointment_id: @appointment.id).exists?
      raise Conflict, "therapist_unavailable" if clash
    end
  end
end
