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
    render_unauthorized(I18n.t("auth.user_not_found")) unless @current_user
  rescue JWT::DecodeError, JWT::ExpiredSignature
    render_unauthorized(I18n.t("auth.invalid_or_expired_token"))
  end

  def render_unauthorized(message)
    render json: { error: message }, status: :unauthorized
  end
end
