module AuthHelpers
  def auth_headers(user)
    { "Authorization" => "Bearer #{Auth::JwtService.encode(user)}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
