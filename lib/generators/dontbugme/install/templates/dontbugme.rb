# frozen_string_literal: true

Dontbugme.configure do |config|
  # config.store = :sqlite
  # config.sqlite_path = "tmp/inspector/inspector.db"

  # Web UI (optional, disabled in production by default)
  # config.enable_web_ui = true
  # config.web_ui_mount_path = "/inspector"

  # Automatic variable tracking (dev only): captures input/output for local var changes
  # config.capture_variable_changes = true

  # Production: use PostgreSQL, async writes, selective recording
  # config.store = :postgresql
  # config.async_store = true
  # config.recording_mode = :selective
  # config.sample_rate = 0.05
  # config.record_on_error = true
end
