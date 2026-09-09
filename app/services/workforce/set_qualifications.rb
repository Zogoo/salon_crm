module Workforce
  # BR-01: a therapist must keep at least one qualification, or they silently
  # drop out of every availability search with no explanation.
  class SetQualifications < ApplicationService
    Invalid = Class.new(StandardError)

    def initialize(staff_profile:, service_ids:, actor: nil)
      @profile = staff_profile
      @service_ids = Array(service_ids).map(&:to_i).uniq
      @actor = actor
    end

    def call
      raise Invalid, "qualifications_required" if @service_ids.empty?
      raise Invalid, "unknown_service" unless Service.where(id: @service_ids).count == @service_ids.size

      ImmediateTransaction.call do
        @profile.staff_qualifications.where.not(service_id: @service_ids).destroy_all
        existing = @profile.staff_qualifications.pluck(:service_id)
        (@service_ids - existing).each { |sid| @profile.staff_qualifications.create!(service_id: sid) }
        AuditLog.record!(auditable: @profile, action: "staff.qualifications.set", actor: @actor,
                         changes: { service_ids: @service_ids })
        @profile.staff_qualifications.reload
      end
    end
  end
end
