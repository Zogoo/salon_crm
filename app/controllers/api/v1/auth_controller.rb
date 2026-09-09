module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :authenticate!, only: %i[sign_in sign_up request_password_reset reset_password]

      def sign_in
        user = Auth::AuthenticateUser.call(email: params[:email], password: params[:password],
                                           otp_code: params[:otp_code])
        if user
          render json: { token: Auth::JwtService.encode(user), user: user_json(user) }
        else
          render json: { error: I18n.t("auth.invalid_credentials") }, status: :unauthorized
        end
      rescue Auth::AuthenticateUser::OtpRequired => e
        # 401 with a distinct code: the password was right, the console just
        # has to ask for the second factor.
        render json: { error: { code: e.message } }, status: :unauthorized
      end

      # Statelessly signed JWTs cannot be revoked server-side without a
      # denylist, so logout is the client discarding the token. Kept as an
      # endpoint because doc 05 specifies it and clients call it.
      def sign_out
        head :no_content
      end

      # --- second factor ---

      # Returns the provisioning URI once; confirming with a valid code is what
      # actually enables it, so a half-finished enrolment cannot lock anyone out.
      def enrol_otp
        secret = ROTP::Base32.random
        current_user.update!(otp_secret: secret, otp_enabled_at: nil)
        render json: {
          secret:,
          otpauth_url: ROTP::TOTP.new(secret, issuer: "Mongolian Massagelab")
                                 .provisioning_uri(current_user.email)
        }, status: :created
      end

      def confirm_otp
        return render_invalid("Start enrolment first", code: "otp_not_started") if current_user.otp_secret.blank?

        verifier = ROTP::TOTP.new(current_user.otp_secret)
        return render_invalid("That code is not valid", code: "otp_invalid") unless
          verifier.verify(params.require(:otp_code).to_s.strip, drift_behind: 30)

        current_user.update!(otp_enabled_at: Time.current)
        render json: { otp_enabled: true }
      end

      # --- password reset ---

      # Always 202, whether or not the address exists: a different response for
      # a known address turns this into an account-enumeration oracle.
      def request_password_reset
        user = User.find_by(email: params[:email].to_s.strip.downcase)
        if user&.active_for_authentication?
          token = user.issue_password_reset!
          UserMailer.password_reset(user, token).deliver_later
        end
        head :accepted
      end

      def reset_password
        user = User.find_by_reset_token(params[:token])
        unless user&.password_reset_valid?
          return render json: { error: { code: "invalid_or_expired_token" } }, status: :unprocessable_content
        end

        user.password = params.require(:password)
        return render_invalid(user.errors.full_messages.join(", ")) unless user.save

        user.clear_password_reset!
        head :no_content
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
