# frozen_string_literal: true

Dontbugme.configure do |config|
  config.store = :sqlite
  config.sqlite_path = Rails.root.join('tmp', 'inspector.db').to_s
  config.enable_web_ui = true
  config.recording_mode = :always
end
