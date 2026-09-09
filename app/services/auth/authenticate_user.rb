module Auth
  # Returns the authenticated user for valid credentials, otherwise nil.
  class AuthenticateUser < ApplicationService
    # Raised rather than returning nil, so the controller can tell "wrong
    # password" apart from "right password, second factor still needed"
    # without inspecting the user record itself.
    OtpRequired = Class.new(StandardError)

    def initialize(email:, password:, otp_code: nil)
      @email = email.to_s.strip.downcase
      @password = password
      @otp_code = otp_code
    end

    def call
      user = User.find_by(email: @email)
      return unless user&.authenticate(@password)
      # BR-02: an offboarded therapist cannot sign back in.
      return unless user.active_for_authentication?

      assert_second_factor!(user)
      user
    end

    private

    def assert_second_factor!(user)
      return unless user.otp_enabled?
      raise OtpRequired, "otp_required" if @otp_code.blank?
      raise OtpRequired, "otp_invalid" unless user.verify_otp(@otp_code)
    end
  end
end
