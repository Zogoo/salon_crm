require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Massagelab
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Serve the Angular build that the production Dockerfile copies into public/.
    config.middleware.use ActionDispatch::Static, "#{root}/public", headers: {
      "cache-control" => "public, max-age=#{1.hour.to_i}"
    }

    config.i18n.default_locale = :en
    config.i18n.available_locales = %i[en]
    config.i18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.yml")]

    # Keep `rails generate` lean: API-only, RSpec + FactoryBot, nothing else.
    config.generators do |g|
      g.test_framework :rspec, fixture: false
      g.factory_bot dir: "spec/factories"
      g.helper false
      g.assets false
      g.template_engine false
      g.jbuilder false
      g.system_tests nil
    end
  end
end
