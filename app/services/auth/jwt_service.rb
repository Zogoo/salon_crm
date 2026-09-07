module Auth
  class JwtService
    ALGORITHM = "HS256"
    DEFAULT_EXPIRY = 24.hours

    class << self
      def encode(user, expiry: DEFAULT_EXPIRY)
        payload = {
          sub: user.id,
          email: user.email,
          exp: expiry.from_now.to_i,
          iat: Time.current.to_i
        }
        JWT.encode(payload, secret_key, ALGORITHM)
      end

      def decode(token)
        JWT.decode(token, secret_key, true, { algorithm: ALGORITHM }).first.symbolize_keys
      end

      private

      def secret_key
        if Rails.env.production?
          ENV.fetch("JWT_SECRET") { raise "JWT_SECRET must be set in production" }
        else
          ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }
        end
      end
    end
  end
end
