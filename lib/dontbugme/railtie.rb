# frozen_string_literal: true

require 'dontbugme'
require 'dontbugme/engine'

module Dontbugme
  class Railtie < ::Rails::Railtie
    config.dontbugme = ActiveSupport::OrderedOptions.new

    initializer 'dontbugme.configure' do |app|
      # Configuration defaults are applied in Configuration#initialize
      # Merge any app-level config (e.g. config.dontbugme.store = :sqlite)
      config = Dontbugme.config
      app.config.dontbugme.each { |k, v| config.send("#{k}=", v) }
    end

    initializer 'dontbugme.subscribers' do
      Dontbugme::Subscribers::ActiveRecord.subscribe
      Dontbugme::Subscribers::NetHttp.subscribe
      Dontbugme::Subscribers::Redis.subscribe
      Dontbugme::Subscribers::Cache.subscribe
      Dontbugme::Subscribers::ActionMailer.subscribe
      Dontbugme::Subscribers::ActiveJob.subscribe
    end

    config.after_initialize do
      # Sidekiq middleware
      if defined?(Sidekiq)
        Sidekiq.configure_server do |config|
          config.server_middleware do |chain|
            chain.add Dontbugme::Middleware::Sidekiq
          end
        end
        Sidekiq.configure_client do |config|
          config.client_middleware do |chain|
            chain.add Dontbugme::Middleware::SidekiqClient
          end
        end
      end

      # Rack middleware
      if defined?(Rails::Application)
        Rails.application.config.middleware.insert 0, Dontbugme::Middleware::Rack
      end
    end
  end
end
