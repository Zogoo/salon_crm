# Role and location-scope checks (doc 04 §4.3).
#
# Rails-native-first (docs/engineering/01-tech-stack.md): this is a concern
# rather than Pundit, because the rules are a handful of role predicates and a
# single location scope, not a policy matrix that earns a dependency.
module Authorizable
  extend ActiveSupport::Concern

  class Forbidden < StandardError; end

  included do
    rescue_from Forbidden, with: :render_forbidden
  end

  private

  def require_role!(*roles)
    raise Forbidden unless roles.map(&:to_s).include?(current_user.role)
  end

  def require_owner!   = require_role!(:owner)
  def require_booking! = (raise Forbidden unless current_user.can_create_appointments?)

  # Out-of-scope records return 404, not 403, so existence is not leaked
  # (doc 05 §2).
  def scoped_location!(id)
    location = Location.find(id)
    raise ActiveRecord::RecordNotFound unless current_user.can_access_location?(location.id)
    location
  end

  def render_forbidden
    render json: { error: I18n.t("auth.forbidden", default: "Not permitted") }, status: :forbidden
  end
end
