class UserMailer < ApplicationMailer
  def welcome(user)
    @user = user
    mail(to: @user.email, subject: I18n.t("user_mailer.welcome.subject"))
  end
end
