# Shared visibility rules and serialisation for everything hanging off a staff
# profile. Kept in one place because the rate-visibility rule (BR-02/BR-03) is
# a security boundary: a Manager must never receive rate fields, whichever
# endpoint they come through.
module StaffScoped
  extend ActiveSupport::Concern

  private

  def staff_profile!
    id = params[:staff_id] || params[:id]
    profile = StaffProfile.includes(:user, :location).find(id)
    raise ActiveRecord::RecordNotFound unless visible?(profile)
    profile
  end

  def visible?(profile)
    return true if current_user.owner?
    return current_user.location_id == profile.location_id if current_user.manager?
    current_user.staff_profile&.id == profile.id
  end

  # Owner sees every rate; a therapist sees only their own; a Manager never
  # sees any. Enforced at the serialiser so no view can leak it.
  def may_see_rates?(profile)
    current_user.owner? || current_user.staff_profile&.id == profile.id
  end

  def staff_json(profile, detail: false)
    json = {
      id: profile.id, display_name: profile.display_name,
      employee_code: profile.employee_code, location_id: profile.location_id,
      status: profile.status, engagement_type: profile.engagement_type,
      can_edit_service_menu: profile.can_edit_service_menu,
      role: profile.user.role, hire_date: profile.hire_date,
      location_name: profile.location&.name
    }
    return json unless detail

    json.merge(
      email: profile.user.email,
      hire_date: profile.hire_date,
      termination_date: profile.termination_date,
      services: profile.services.map { |s| { id: s.id, name: s.name } }
    ).tap { |j| j[:session_rates] = current_ladder(profile) if may_see_rates?(profile) }
  end

  # The ladder in force today — the full history lives at /session_rates.
  def current_ladder(profile)
    profile.staff_session_rates
           .where(effective_to: nil).order(:duration_minutes)
           .map { |r| { duration_minutes: r.duration_minutes, rate_cents: r.rate_cents,
                        effective_from: r.effective_from } }
  end
end
