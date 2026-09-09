class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    mail(to: @user.email, subject: I18n.t("user_mailer.welcome.subject"))
  end

  # The raw token is passed in rather than read off the record, because only
  # its digest is stored.
  def password_reset(user, token)
    @user = user
    @reset_url = "#{ENV.fetch('APP_FRONTEND_URL', 'http://localhost:4211')}/reset-password?token=#{token}"
    mail(to: @user.email, subject: "Reset your Mongolian Massagelab password")
  end
end
