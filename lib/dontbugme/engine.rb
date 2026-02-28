# frozen_string_literal: true

module Dontbugme
  class Engine < ::Rails::Engine
    isolate_namespace Dontbugme

    # Mount in config/routes.rb:
    #   mount Dontbugme::Engine, at: '/inspector'
    # Enable/disable via config.enable_web_ui (default: true in dev, false in prod)
  end
end
