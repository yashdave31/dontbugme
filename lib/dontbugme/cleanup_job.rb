# frozen_string_literal: true

module Dontbugme
  class CleanupJob
    def self.perform
      store = Dontbugme.store
      return unless store

      config = Dontbugme.config
      retention = config.retention
      return unless retention

      cutoff = Time.now - retention
      store.cleanup(before: cutoff)
    end
  end
end
