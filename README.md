# Dontbugme

A flight recorder for Rails applications. Reconstruct the full execution story of Sidekiq jobs and HTTP requests — see exactly what database queries ran, what HTTP services were called, what exceptions were raised, with source locations pointing to your code.

## Installation

Add to your Gemfile:

```ruby
gem 'dontbugme'
```

Then run:

```bash
bundle install
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

Add custom spans and snapshots within a trace:

```ruby
trace = Dontbugme.trace("checkout flow") do
  Dontbugme.span("Calculate tax") do
    tax = order.calculate_tax
  end
  Dontbugme.snapshot(user: user.attributes.slice("id", "email"), total: order.total)
  Dontbugme.tag(customer_tier: "enterprise")
end
```

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

### Web UI (optional)

A lightweight web interface to browse traces. **Disabled by default in production.** Enable in development:

```ruby
# config/initializers/dontbugme.rb
Dontbugme.configure do |config|
  config.enable_web_ui = true  # default: true in dev, false in prod
  config.web_ui_mount_path = '/inspector'
end
```

Add to `config/routes.rb`:

```ruby
mount Dontbugme::Engine, at: '/inspector' if Dontbugme.config.enable_web_ui
```

Then visit `/inspector` to browse traces, search, and compare.

### Configuration

Create `config/initializers/dontbugme.rb`:

```ruby
Dontbugme.configure do |config|
  config.store = :sqlite
  config.sqlite_path = "tmp/inspector/inspector.db"
  config.recording_mode = :always
  config.capture_sql_binds = true
  config.source_mode = :full
end
```

## Storage

- **SQLite** (default): Zero config. Data at `tmp/inspector/inspector.db`
- **PostgreSQL**: Uses your Rails DB. Set `config.store = :postgresql`
- **Memory**: For tests. Traces lost on process exit.

## Cleanup

Traces are ephemeral. Run cleanup to enforce retention:

```ruby
Dontbugme::CleanupJob.perform
```

Schedule via cron or Sidekiq to run periodically.

## Requirements

- Ruby >= 3.0
- Rails >= 7.0 (for full integration)
- Sidekiq >= 7.0 (optional, for job tracing)

## License

MIT
