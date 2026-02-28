# Dontbugme

A flight recorder for Rails applications. Reconstruct the full execution story of Sidekiq jobs and HTTP requests — see exactly what database queries ran, what HTTP services were called, what exceptions were raised, with source locations pointing to your code.

## Quick Start

Get up and running in under 2 minutes:

**1. Add the gem and install**

```ruby
# Gemfile
gem 'dontbugme'
```

```bash
bundle install
```

**2. Run the installer** (creates config and mounts the Web UI)

```bash
rails g dontbugme:install
```

This adds `config/initializers/dontbugme.rb` and mounts the engine at `/inspector` in your routes.

**3. Start your app and generate traffic**

```bash
rails s          # Start the server
# In another terminal, if you use Sidekiq:
bundle exec sidekiq
```

Make an HTTP request (visit a page, hit an API) or run a Sidekiq job. Dontbugme records automatically in development.

**4. View traces**

**Option A — Web UI (easiest):** Open [http://localhost:3000/inspector](http://localhost:3000/inspector) in your browser. Browse, search, and compare traces.

**Option B — CLI:** From your Rails app root (so it finds the SQLite DB):

```bash
bundle exec dontbugme list                    # List recent traces
bundle exec dontbugme show <trace_id>         # Show a trace
bundle exec dontbugme search --status=error   # Find failed traces
```

That's it. No database migrations needed — SQLite is used by default in development (`tmp/inspector/inspector.db`).

---

## Installation

Add to your Gemfile:

```ruby
gem 'dontbugme'
```

Then run:

```bash
bundle install
rails g dontbugme:install
```

## Usage

### Automatic Recording

Dontbugme automatically records:

- **Sidekiq jobs** — via Sidekiq server middleware
- **HTTP requests** — via Rack middleware
- **SQL queries** — via ActiveSupport::Notifications
- **HTTP calls** — Net::HTTP (including Faraday, which uses it)
- **Redis** — Redis gem operations
- **Cache** — Rails cache read/write/delete
- **Mailer** — ActionMailer deliveries
- **Job enqueue** — Active Job enqueues

In development, recording is on by default. Run your app normally, then inspect:

```bash
# List recent traces
bundle exec dontbugme list

# Show a specific trace
bundle exec dontbugme show tr_abc123

# Filter spans
bundle exec dontbugme show tr_abc123 --only=sql
bundle exec dontbugme show tr_abc123 --slow=10

# JSON output
bundle exec dontbugme show tr_abc123 --json
```

### Manual Tracing

Wrap any block to capture a trace:

```ruby
trace = Dontbugme.trace("my debug session") do
  User.find(42)
  Order.where(user_id: 42).count
end

puts trace.to_timeline
# Or: trace.spans, trace.status, trace.duration_ms
```

### Manual Spans and Snapshots

Add custom spans and snapshots within a trace. Spans capture the **return value** by default so you can see outputs in the UI:

```ruby
trace = Dontbugme.trace("checkout flow") do
  Dontbugme.span("Calculate tax") do
    tax = order.calculate_tax  # output shown in UI
  end
  Dontbugme.snapshot(user: user.attributes.slice("id", "email"), total: order.total)
  Dontbugme.tag(customer_tier: "enterprise")
end
```

Use `capture_output: false` to skip capturing the return value for sensitive data.

### Span Categories

Access spans by category for assertions or analysis:

```ruby
trace.spans.sql        # SQL queries
trace.spans.http       # HTTP calls
trace.spans.redis      # Redis operations
trace.spans.category(:mailer)  # Any category
```

### Search

```bash
bundle exec dontbugme search --status=error --class=SendInvoiceJob --limit=10
```

### Trace Diff

Compare two executions to see what changed:

```bash
bundle exec dontbugme diff tr_success tr_failed
```

Shows IDENTICAL, CHANGED, MISSING, and NEW spans between the two traces.

### Correlation Chain

When a request enqueues jobs, they share a `correlation_id`. Follow the full chain:

```bash
bundle exec dontbugme trace tr_request_id --follow
```

Shows all traces (request + enqueued jobs) with the same correlation ID. Correlation IDs are automatically propagated from HTTP requests to Sidekiq jobs (and from job to child job) when using the Rails integration.

### Web UI

A lightweight web interface to browse traces. The installer mounts it at `/inspector`. It's **enabled by default in development** and **disabled in production**.

Visit `/inspector` to browse traces, search, and compare. Tweak in `config/initializers/dontbugme.rb`:

```ruby
config.enable_web_ui = true
config.web_ui_mount_path = '/inspector'
```

### Configuration

Edit `config/initializers/dontbugme.rb` (created by the installer):

```ruby
Dontbugme.configure do |config|
  config.store = :sqlite
  config.sqlite_path = "tmp/inspector/inspector.db"
  config.recording_mode = :always
  config.capture_sql_binds = true
  config.source_mode = :full

  # Capture outputs for debugging (development only)
  config.capture_span_output = true      # return values from Dontbugme.span
  config.capture_http_body = true       # HTTP response bodies
  config.capture_redis_return_values = true  # Redis command return values
end
```

## Storage

- **SQLite** (default): Zero config. Data at `tmp/inspector/inspector.db`
- **PostgreSQL**: Uses your Rails DB. Set `config.store = :postgresql`
- **Memory**: For tests. Traces lost on process exit.

## Production

In production, Dontbugme uses safer defaults: PostgreSQL storage, async writes, selective recording, and the Web UI disabled. No extra setup is required if you use PostgreSQL — the gem creates the `dontbugme_traces` table automatically.

### Default production behavior

- **Store**: PostgreSQL (uses your Rails DB connection)
- **Web UI**: Disabled — enable only if you add authentication
- **Recording**: Selective — always records failures (`record_on_error`), samples successful traces
- **Async writes**: Enabled to avoid blocking requests/jobs

### Recommended configuration

```ruby
# config/initializers/dontbugme.rb
Dontbugme.configure do |config|
  config.store = :postgresql
  config.async_store = true

  # Sample 5% of successful traces to limit storage
  config.recording_mode = :selective
  config.sample_rate = 0.05
  config.record_on_error = true   # Always capture failures

  # Optional: record only specific jobs
  # config.record_jobs = %w[SendInvoiceJob ProcessPaymentJob]
  # config.record_requests = :all  # or a proc for custom logic
end
```

### Enabling the Web UI in production

If you need the Web UI in production (e.g. for on-call debugging), **protect it with authentication**:

```ruby
# config/initializers/dontbugme.rb
Dontbugme.configure do |config|
  config.enable_web_ui = true
  config.web_ui_mount_path = '/inspector'
end
```

Then add authentication in your routes (e.g. with Devise, `authenticate` before the mount, or HTTP basic auth via a constraint).

### Cleanup and retention

Production defaults to 24-hour retention. Schedule cleanup to enforce it:

```ruby
# config/schedule.rb (whenever) or a Sidekiq cron job
Dontbugme::CleanupJob.perform
```

Example with Sidekiq:

```ruby
# app/jobs/dontbugme_cleanup_job.rb
class DontbugmeCleanupJob < ApplicationJob
  queue_as :low

  def perform
    Dontbugme::CleanupJob.perform
  end
end
# Schedule daily via sidekiq-cron, whenever, or similar
```

### CLI in production

Run the CLI from your production app directory (or a deploy host with DB access). It uses your Rails DB config:

```bash
RAILS_ENV=production bundle exec dontbugme list
RAILS_ENV=production bundle exec dontbugme search --status=error --limit=50
```

## Cleanup

Traces are ephemeral. Run `Dontbugme::CleanupJob.perform` to enforce retention. See [Production](#production) for scheduling via Sidekiq or cron.

## Requirements

- Ruby >= 3.0
- Rails >= 7.0 (for full integration)
- Sidekiq >= 7.0 (optional, for job tracing)

## License

MIT
