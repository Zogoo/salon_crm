module Workforce
  # Profile edits. Rates and qualifications have their own endpoints, because
  # both are effective-dated or set-based and do not belong in a PATCH.
  class UpdateStaff < ApplicationService
    Invalid = Class.new(StandardError)

    PROFILE_FIELDS = %i[display_name employee_code location_id engagement_type
                        hire_date status can_edit_service_menu].freeze
    USER_FIELDS    = %i[email].freeze

    def initialize(staff_profile:, attrs:, actor: nil)
      @profile = staff_profile
      @attrs = attrs.to_h.symbolize_keys
      @actor = actor
    end

    def call
      ImmediateTransaction.call do
        @profile.update!(@attrs.slice(*PROFILE_FIELDS))
        user_changes = @attrs.slice(*USER_FIELDS).compact_blank
        @profile.user.update!(user_changes) if user_changes.any?
        # BR-03a: a therapist works at one location at a time, so moving the
        # profile moves the Manager login that is pinned to it too.
        @profile.user.update!(location_id: @profile.location_id) if @profile.user.manager?

        AuditLog.record!(auditable: @profile, action: "staff.updated", actor: @actor,
                         changes: @attrs.slice(*PROFILE_FIELDS, *USER_FIELDS))
        @profile
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.record.errors.full_messages.join(", ")
    end
  end
end
