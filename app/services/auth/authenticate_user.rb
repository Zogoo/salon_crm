module Auth
  # Returns the authenticated user for valid credentials, otherwise nil.
  class AuthenticateUser < ApplicationService
    def initialize(email:, password:)
      @email = email.to_s.strip.downcase
      @password = password
    end

    def call
      user = User.find_by(email: @email)
      return unless user&.authenticate(@password)

      user
    end
  end
end
