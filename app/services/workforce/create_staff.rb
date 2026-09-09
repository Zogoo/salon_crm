module Workforce
  # Doc 05 §6: onboarding is one call — login, profile, location, the services
  # they are qualified for, and the pay ladder. Half a therapist is worse than
  # none: one without qualifications cannot be assigned, and one without a
  # ladder books fine and then fails at payroll.
  class CreateStaff < ApplicationService
    Invalid = Class.new(StandardError)

    # Onboarding mints workforce logins only. Owner is deliberately absent:
    # it is the one role allowed to reach this endpoint, so accepting it here
    # would let a hijacked Owner session leave a second Owner behind, and that
    # account outlives the session that made it. Promoting someone to Owner is
    # a deliberate act with its own path, not a field on the hiring form.
    ASSIGNABLE_ROLES = %w[staff manager].freeze

    def initialize(attrs:, actor: nil)
      @attrs = attrs.to_h.symbolize_keys
      @actor = actor
    end

    def call
      location = Location.find(@attrs.fetch(:location_id))
      role = requested_role

      ImmediateTransaction.call do
        user = User.create!(
          email: @attrs.fetch(:email), name: @attrs.fetch(:display_name),
          password: @attrs[:password].presence || SecureRandom.base58(16),
          role: role, status: "active",
          location: (location if role == "manager")
        )

        profile = StaffProfile.create!(
          user:, location:,
          display_name: @attrs.fetch(:display_name),
          employee_code: @attrs[:employee_code].presence || next_employee_code(location),
          engagement_type: @attrs.fetch(:engagement_type, "contractor_1099"),
          hire_date: @attrs[:hire_date].presence || location.today,
          status: "active"
        )

        set_qualifications!(profile)
        set_rates!(profile)

        AuditLog.record!(auditable: profile, action: "staff.created", actor: @actor,
                         changes: { email: user.email, role: user.role })
        profile
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.record.errors.full_messages.join(", ")
    end

    private

    def requested_role
      role = @attrs.fetch(:role, "staff").to_s
      return role if ASSIGNABLE_ROLES.include?(role)
      raise Invalid, "role must be one of: #{ASSIGNABLE_ROLES.join(', ')}"
    end

    def next_employee_code(location)
      prefix = location.name.parameterize.upcase.first(3)
      n = StaffProfile.where("employee_code LIKE ?", "#{prefix}-%").count + 1
      format("%s-%03d", prefix, n)
    end

    def set_qualifications!(profile)
      Array(@attrs[:service_ids]).map(&:to_i).uniq.each do |sid|
        profile.staff_qualifications.create!(service_id: sid, active: true)
      end
    end

    # Managers are on a flat monthly rate and never earn per session (BR-36),
    # so a session ladder is neither required nor meaningful for them.
    def set_rates!(profile)
      if profile.manager?
        return if @attrs[:monthly_rate_cents].blank?

        profile.staff_monthly_rates.create!(
          amount_cents: @attrs[:monthly_rate_cents].to_i,
          effective_from: @attrs[:rates_effective_from].presence || profile.hire_date,
          created_by_user: @actor
        )
      elsif @attrs[:session_rates].present?
        SetSessionRates.call(
          staff_profile: profile, rates: normalised_rates,
          effective_from: @attrs[:rates_effective_from].presence || profile.hire_date,
          actor: @actor, note: "Onboarding"
        )
      end
    end

    def normalised_rates
      Array(@attrs[:session_rates]).map { |r| r.to_h.symbolize_keys }
    end
  end
end
