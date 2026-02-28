# frozen_string_literal: true

module Dontbugme
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def add_route
        route "mount Dontbugme::Engine, at: '/inspector' if Dontbugme.config.enable_web_ui"
      end

      def create_initializer
        template 'dontbugme.rb', 'config/initializers/dontbugme.rb'
      end
    end
  end
end
