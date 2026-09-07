module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :authenticate!, only: %i[sign_in sign_up]

      def sign_in
        user = Auth::AuthenticateUser.call(email: params[:email], password: params[:password])
        if user
          render json: { token: Auth::JwtService.encode(user), user: user_json(user) }
        else
          render json: { error: I18n.t("auth.invalid_credentials") }, status: :unauthorized
        end
      end

      def sign_up
        user = User.new(sign_up_params)
        if user.save
          UserMailer.welcome(user).deliver_later
          render json: { token: Auth::JwtService.encode(user), user: user_json(user) }, status: :created
        else
          render json: { error: user.errors.full_messages }, status: :unprocessable_content
        end
      end

      def me
        render json: user_json(current_user)
      end

      private

      def sign_up_params
        params.permit(:email, :password, :password_confirmation, :name)
      end
    end
  end
end
