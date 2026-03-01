# frozen_string_literal: true

require 'dontbugme'
require 'dontbugme/engine'

module Dontbugme
  class Railtie < ::Rails::Railtie
    config.dontbugme = ActiveSupport::OrderedOptions.new

    initializer 'dontbugme.configure' do |app|
      config = Dontbugme.config
      app.config.dontbugme.each { |k, v| config.send("#{k}=", v) }
    end

    initializer 'dontbugme.middleware' do |app|
      app.middleware.insert 0, Dontbugme::Middleware::Rack
    end

    initializer 'dontbugme.subscribers' do
      Dontbugme::Subscribers::ActiveRecord.subscribe
      Dontbugme::Subscribers::NetHttp.subscribe
      Dontbugme::Subscribers::Redis.subscribe
      Dontbugme::Subscribers::Cache.subscribe
      Dontbugme::Subscribers::ActionMailer.subscribe
      Dontbugme::Subscribers::ActiveJob.subscribe
      Dontbugme::VariableTracker.subscribe
    end

    config.after_initialize do
      if defined?(Sidekiq)
        Sidekiq.configure_server do |cfg|
          cfg.server_middleware do |chain|
            chain.add Dontbugme::Middleware::Sidekiq
          end
        end
        Sidekiq.configure_client do |cfg|
          cfg.client_middleware do |chain|
            chain.add Dontbugme::Middleware::SidekiqClient
          end
        end
      end
    end
  end
end
