module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  private

  def authenticate!
    token = request.headers["Authorization"]&.split("Bearer ")&.last
    return render_unauthorized(I18n.t("auth.missing_token")) unless token

    payload = Auth::JwtService.decode(token)
    @current_user = User.find_by(id: payload[:sub])
    return render_unauthorized(I18n.t("auth.user_not_found")) unless @current_user

    # BR-02: a disabled account keeps its token until expiry, so the check has
    # to happen here rather than only at sign-in.
    return render_unauthorized(I18n.t("auth.account_disabled", default: "Account disabled")) unless
      @current_user.active_for_authentication?
  rescue JWT::DecodeError, JWT::ExpiredSignature
    render_unauthorized(I18n.t("auth.invalid_or_expired_token"))
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end
end
