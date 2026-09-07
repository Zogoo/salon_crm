class ApplicationController < ActionController::API
  include Authenticatable
  include Authorizable

  before_action :set_locale
  before_action :authenticate!

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable

  private

  def set_locale
    locale = request.headers["X-Locale"]&.to_sym
    I18n.locale = I18n.available_locales.include?(locale) ? locale : I18n.default_locale
  end

  def user_json(user)
    {
      id: user.id,
      email: user.email,
      name: user.name,
      role: user.role,
      location_id: user.location_id,
      accessible_location_ids: user.accessible_location_ids,
      staff_profile_id: user.staff_profile&.id,
      avatar_url: avatar_url(user)
    }
  end

  def avatar_url(user)
    return nil unless user.avatar.attached?

    rails_blob_url(
      user.avatar,
      host: request.host,
      port: request.optional_port,
      protocol: request.protocol.delete_suffix("://")
    )
  end

  def render_not_found
    render json: { error: I18n.t("record.not_found") }, status: :not_found
  end

  def render_unprocessable(exception)
    render json: { error: exception.record&.errors&.full_messages || [ exception.message ] },
           status: :unprocessable_content
  end
end
