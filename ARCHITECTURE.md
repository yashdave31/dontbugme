# Inspector — Expanded Architecture

Inspector is a Ruby gem that acts as a **flight recorder** for Rails applications. It captures a structured, replayable trace of everything that happens during a unit of work — a Sidekiq job, a controller request, a rake task, or any block of code — so developers can debug what *actually* happened without reproducing it.

---

## The Real Problem

Today, when a developer suspects something went wrong — a job produced incorrect data, a request was slow, a side effect didn't fire — they follow the same painful loop:

1. Read the logs (noisy, interleaved with other requests, missing context)
2. Open a Rails console, load the same data, run each line manually
3. Realize the state has changed since the original execution
4. Add `Rails.logger.info` everywhere, redeploy, wait for it to happen again
5. Maybe reproduce it. Maybe not. Hours lost either way.

The fundamental gap: **there is no way to look at a completed execution and understand exactly what it did, in order, with the code locations that triggered each action.**

Inspector fills that gap.

---

## Scope: Not Just Sidekiq

The initial design focused on Sidekiq jobs. The gem should support any **unit of work**:

| Unit of Work     | How It Starts                        | Identifier          |
|------------------|--------------------------------------|----------------------|
| Sidekiq Job      | Sidekiq middleware (automatic)       | `jid`                |
| HTTP Request     | Rack middleware (automatic)          | `request_id`         |
| Rake Task        | `Inspector.trace("task:name") { }` | custom label         |
| Console / Ad-hoc | `Inspector.trace("debugging") { }`  | custom label         |

All four produce the same data structure: a **Trace** containing an ordered list of **Spans**.

---

## Core Concepts

### Trace

A Trace is the top-level container. One trace per unit of work.

```
Trace
├── id:           "tr_a1b2c3"
├── kind:         :sidekiq | :request | :custom
├── identifier:   "SendInvoiceJob (jid=abc123)" | "POST /api/charges"
├── started_at:   2025-02-28 14:30:00.000
├── finished_at:  2025-02-28 14:30:00.065
├── duration_ms:  65
├── status:       :success | :error
├── error:        nil | { class: "RuntimeError", message: "...", backtrace: [...] }
├── metadata:     { queue: "critical", args: [...], user_id: 42 }
├── correlation_id: "corr_x9y8z7"  (links request → job chains)
└── spans:        [...]
```

### Span

A Span is a single recorded event within a trace. Every I/O operation, every side effect.

```
Span
├── id:           "sp_d4e5f6"
├── category:     :sql | :http | :redis | :cache | :mailer | :enqueue | :custom
├── operation:    "SELECT" | "POST" | "SET" | "deliver" | ...
├── detail:       "SELECT * FROM users WHERE id = 42"
├── payload:      { table: "users", rows_affected: 1, binds: [...] }
├── started_at:   relative offset from trace start (5.2ms)
├── duration_ms:  3.1
├── source:       "app/services/invoice_service.rb:47 in `find_user`"
└── children:     [...]  (for nested operations like transactions)
```

### The Critical Field: `source`

This is what makes Inspector different from every APM tool and logger.

Every span records which line of **your application code** triggered it. Not the framework internals — your code. When a developer reads a trace, they can go straight to the exact line that caused each database query, each HTTP call, each Redis write.

Implementation: `caller_locations` filtered to paths matching `app/`, `lib/`, or a configurable include list. We skip framework frames (`activerecord`, `activesupport`, `net/http` internals) and surface the first application frame.

This transforms a trace from "here's what the database saw" to "here's what YOUR code did."

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────┐
│                    Your Rails App                     │
│                                                       │
│  ┌─────────┐  ┌──────────┐  ┌─────────────────────┐ │
│  │ Sidekiq │  │   Rack   │  │ Inspector.trace { } │ │
│  │Middleware│  │Middleware │  │   (manual block)    │ │
│  └────┬─────┘  └─────┬─────┘  └──────────┬──────────┘ │
│       │              │                    │            │
│       └──────────────┴────────────────────┘            │
│                      │                                 │
│              ┌───────▼────────┐                        │
│              │    Recorder    │  (creates trace,       │
│              │                │   manages context)     │
│              └───────┬────────┘                        │
│                      │                                 │
│              ┌───────▼────────┐                        │
│              │    Context     │  (thread-local,        │
│              │                │   holds current trace) │
│              └───────┬────────┘                        │
│                      │                                 │
│    ┌─────────────────┼─────────────────────┐          │
│    │                 │                     │          │
│    ▼                 ▼                     ▼          │
│ ┌──────┐      ┌──────────┐          ┌──────────┐    │
│ │  SQL │      │   HTTP   │          │  Redis   │    │
│ │Subscr│      │  Subscr  │          │  Subscr  │    │
│ └──┬───┘      └────┬─────┘          └────┬─────┘    │
│    │               │                     │          │
│    └───────────────┴─────────────────────┘          │
│                    │                                 │
│            ┌───────▼────────┐                        │
│            │     Store      │                        │
│            │  (pluggable)   │                        │
│            └───────┬────────┘                        │
│                    │                                 │
└────────────────────┼─────────────────────────────────┘
                     │
          ┌──────────┼───────────┐
          ▼          ▼           ▼
      ┌────────┐ ┌────────┐ ┌────────┐
      │ SQLite │ │Postgres│ │ Memory │
      └────────┘ └────────┘ └────────┘
```

### Layer Responsibilities

**1. Middleware Layer** — Entry points that create and finalize traces.
Zero configuration for Sidekiq and Rack. Automatically installed via a Railtie.

**2. Recorder** — Orchestrator. Starts a trace, installs the context, ensures the trace is finalized and stored even if an exception occurs.

**3. Context** — Thread-local (fiber-local in Ruby 3.x) storage holding the current active trace. Subscribers check the context — if there's no active trace, they no-op. This means subscribers are *always* installed but cost nothing when recording is off.

**4. Subscribers** — Listen to events (mostly via `ActiveSupport::Notifications`) and append spans to the current trace. Each subscriber is a self-contained module responsible for one category of I/O.

**5. Store** — Persists completed traces. Pluggable backend. Handles writes (save trace), reads (find trace by ID), and cleanup (retention policy).

---

## Instrumentation: What Gets Captured

### Automatically (zero config)

| Category | Source | Events Captured |
|----------|--------|-----------------|
| **SQL** | `ActiveSupport::Notifications` (`sql.active_record`) | All queries, bind params, table name, operation type (SELECT/INSERT/UPDATE/DELETE), rows affected, transaction boundaries (BEGIN/COMMIT/ROLLBACK) |
| **HTTP** | Patch `Net::HTTP` + adapters for Faraday/HTTParty | Method, URL, request headers (configurable), status code, response time, response size |
| **Redis** | `Redis::Client` instrumentation | Command, key(s), duration |
| **Cache** | `ActiveSupport::Notifications` (`cache_*.active_support`) | Read/write/delete/exist, key, hit/miss, duration |
| **Mailer** | `ActiveSupport::Notifications` (`deliver.action_mailer`) | Mailer class, action, recipients, subject |
| **Job Enqueue** | `ActiveSupport::Notifications` (`enqueue.active_job`) | Job class, arguments, queue, scheduled_at |

### Manually (opt-in, for richer traces)

```ruby
# Wrap a logical section with a named span
Inspector.span("Calculate tax") do
  tax = tax_service.compute(invoice)
end

# Snapshot a value at a point in time
Inspector.snapshot(
  user: user.attributes.slice("id", "email", "plan"),
  invoice_total: invoice.total_cents
)

# Tag the current trace with searchable metadata
Inspector.tag(customer_tier: "enterprise", region: "us-east")
```

The manual API is the escape hatch. It lets developers instrument the *logic* — not just the I/O. The combination of automatic I/O capture and manual logic annotation gives a complete picture.

---

## Storage Layer

### Design

The store interface is minimal:

```ruby
module Inspector
  module Store
    class Base
      def save_trace(trace)     = raise NotImplementedError
      def find_trace(trace_id)  = raise NotImplementedError
      def search(filters = {})  = raise NotImplementedError
      def cleanup(before:)      = raise NotImplementedError
    end
  end
end
```

### Backends

**SQLite (default for development)**
- Zero configuration. Single file at `tmp/inspector/inspector.db`.
- Excellent for local debugging. Portable — you can share a `.db` file with a colleague.
- Traces stored as JSON blobs with indexed metadata columns for fast lookup.
- Schema: `traces` table with columns: `id`, `kind`, `identifier`, `status`, `started_at`, `duration_ms`, `metadata_json`, `spans_json`, `error_json`.

**PostgreSQL (recommended for staging/production)**
- Uses a dedicated `inspector_traces` table in your existing database (or a separate database).
- Same schema as SQLite, but benefits from concurrent access and better query performance.
- Installed via a Rails migration generator: `rails generate inspector:install`

**Memory (for testing)**
- In-memory hash. Traces are lost on process exit.
- Useful for test suites: assert that a certain operation produced expected spans.

### Retention

Traces are ephemeral debugging data, not permanent records. The store enforces retention:

```ruby
Inspector.configure do |config|
  config.retention = 72.hours   # default: keep traces for 3 days
  config.max_traces = 10_000    # safety cap
end
```

Cleanup runs lazily (on write) or via a scheduled job: `Inspector::CleanupJob`.

---

## Recording Modes

Not every execution needs recording. Inspector supports multiple modes:

### Development (default: always-on)

Every job and request is traced. This is the whole point — when something goes wrong, the trace is already there.

### Production (default: off, selective recording)

```ruby
Inspector.configure do |config|
  config.recording_mode = :selective

  # Record specific job classes
  config.record_jobs = ["SendInvoiceJob", "SyncInventoryJob"]

  # Record requests matching a condition
  config.record_requests = ->(env) { env["HTTP_X_INSPECTOR"] == "1" }

  # Always record failures (even if not in the record list)
  config.record_on_error = true

  # Sample 5% of all traffic
  config.sample_rate = 0.05
end
```

The `record_on_error` flag is particularly powerful: Inspector buffers spans in memory during execution. If the execution succeeds and recording isn't enabled, the buffer is discarded (cheap). If an exception occurs, the buffer is flushed to the store. You get traces for every failure with near-zero overhead for successes.

---

## The Inspection Interface

### CLI

The primary interface. Fast, no browser needed, works over SSH.

```bash
# Find recent traces
$ bundle exec inspector list
┌─────────────┬──────────────────────┬────────┬──────────┬─────────────────────┐
│ Trace ID    │ Identifier           │ Status │ Duration │ Time                │
├─────────────┼──────────────────────┼────────┼──────────┼─────────────────────┤
│ tr_a1b2c3   │ SendInvoiceJob       │ ✓      │ 65ms     │ 2 min ago           │
│ tr_d4e5f6   │ POST /api/charges    │ ✗      │ 2100ms   │ 5 min ago           │
│ tr_g7h8i9   │ SyncInventoryJob     │ ✓      │ 340ms    │ 12 min ago          │
└─────────────┴──────────────────────┴────────┴──────────┴─────────────────────┘

# Inspect a single trace
$ bundle exec inspector show tr_a1b2c3

  SendInvoiceJob (jid=abc123)
  Status: success | Duration: 65ms | Recorded: 2 min ago

  TIMELINE
  ───────────────────────────────────────────────────────
  0.0ms   ▸ Job started
  5.2ms   ▸ SQL SELECT users WHERE id = 42                       (3.1ms)
            → app/services/invoice_service.rb:47 in `find_user`
  8.3ms   ▸ SQL BEGIN
 10.1ms   ▸ SQL INSERT INTO invoices (user_id, amount, ...)      (1.8ms)
            → app/services/invoice_service.rb:52 in `create_invoice`
 25.0ms   ▸ HTTP POST https://billing.internal/charge → 200      (14.9ms)
            → app/services/payment_gateway.rb:18 in `charge`
 50.3ms   ▸ SQL UPDATE invoices SET status = 'paid'              (2.1ms)
            → app/services/invoice_service.rb:71 in `mark_paid`
 52.4ms   ▸ ENQUEUE SendReceiptEmailJob [invoice_id: 99]
            → app/services/invoice_service.rb:73 in `send_receipt`
 60.0ms   ▸ SQL COMMIT
 65.0ms   ▸ Job finished

# Filter spans
$ bundle exec inspector show tr_a1b2c3 --only=sql
$ bundle exec inspector show tr_a1b2c3 --only=http
$ bundle exec inspector show tr_a1b2c3 --slow=10   # spans > 10ms

# JSON output for piping/scripting
$ bundle exec inspector show tr_a1b2c3 --json

# Search across traces
$ bundle exec inspector search --class=SendInvoiceJob --status=error --since=1h
```

### Programmatic API (for tests and scripts)

```ruby
# In an RSpec test — assert your code produces expected side effects
trace = Inspector.trace("test: invoice creation") do
  InvoiceService.new(user).create(amount: 5000)
end

expect(trace.spans.sql.count).to eq(4)
expect(trace.spans.http).to contain_exactly(
  having_attributes(operation: "POST", detail: /billing.internal/)
)
expect(trace.status).to eq(:success)
```

This turns Inspector into a **testing tool** — assert that a code path produces exactly the side effects you expect. No more "run it and check the database manually."

### Web UI (optional, Rails Engine)

A mounted Rails engine at `/inspector` (development only by default). Browse traces, search, view timelines. Built with Hotwire for a fast, modern feel without a JS build step.

```ruby
# config/routes.rb
mount Inspector::Engine, at: "/inspector" if Rails.env.development?
```

The web UI is the lowest-priority interface. CLI and programmatic API come first.

---

## Killer Feature: Trace Diff

When a developer says "this job used to work, now it doesn't" — the most valuable thing is seeing what changed between two executions.

```bash
$ bundle exec inspector diff tr_old123 tr_new456

  SendInvoiceJob — Execution Diff
  ─────────────────────────────────────────────────────

  Trace A: tr_old123 (success, 65ms)
  Trace B: tr_new456 (error, 2100ms)

  IDENTICAL  SQL SELECT users WHERE id = 42
  IDENTICAL  SQL BEGIN
  IDENTICAL  SQL INSERT INTO invoices (...)
  CHANGED    HTTP POST billing.internal/charge
               A: 200 OK (15ms)
               B: 503 Service Unavailable (2002ms) ← timeout
  MISSING    SQL UPDATE invoices SET status = 'paid'    ← never reached in B
  MISSING    SQL COMMIT                                  ← never reached in B
  NEW        ROLLBACK                                    ← only in B
  NEW        EXCEPTION BillingTimeoutError               ← only in B
```

The diff operates on the *sequence of spans*, not text. It aligns spans by category + operation + detail (normalized), then reports identical, changed, missing, and new.

This alone saves hours of debugging.

---

## Trace Correlation

A single user action often spans multiple units of work:

```
Request: POST /api/orders
  └─ enqueues: ChargePaymentJob (jid=abc)
       └─ enqueues: SendReceiptEmailJob (jid=def)
       └─ enqueues: UpdateInventoryJob (jid=ghi)
```

Inspector links these via a `correlation_id` that flows from request → job → child job.

```bash
$ bundle exec inspector trace tr_request --follow

  POST /api/orders (tr_req001, 120ms, success)
  ├── ChargePaymentJob (tr_job_abc, 65ms, success)
  │   ├── SendReceiptEmailJob (tr_job_def, 30ms, success)
  │   └── UpdateInventoryJob (tr_job_ghi, 80ms, error)  ← problem here
```

This lets you see the full causal chain of a user action across async boundaries.

---

## Gem Structure

```
inspector/
├── lib/
│   ├── inspector.rb                         # Public API, configuration
│   └── inspector/
│       ├── version.rb
│       ├── configuration.rb                 # Config DSL
│       ├── trace.rb                         # Trace data structure
│       ├── span.rb                          # Span data structure
│       ├── context.rb                       # Thread/Fiber-local current trace
│       ├── recorder.rb                      # Orchestrates trace lifecycle
│       ├── source_location.rb               # Caller filtering logic
│       ├── subscribers/                     # One file per I/O category
│       │   ├── base.rb
│       │   ├── active_record.rb             # sql.active_record
│       │   ├── net_http.rb                  # Monkey-patch Net::HTTP
│       │   ├── redis.rb                     # Redis client instrumentation
│       │   ├── cache.rb                     # cache_*.active_support
│       │   ├── action_mailer.rb             # deliver.action_mailer
│       │   └── active_job.rb               # enqueue.active_job
│       ├── middleware/
│       │   ├── sidekiq.rb                   # Sidekiq server middleware
│       │   └── rack.rb                      # Rack middleware for requests
│       ├── store/
│       │   ├── base.rb                      # Interface
│       │   ├── sqlite.rb
│       │   ├── postgresql.rb
│       │   └── memory.rb
│       ├── formatters/
│       │   ├── timeline.rb                  # CLI timeline output
│       │   ├── json.rb                      # JSON export
│       │   └── diff.rb                      # Trace diffing logic
│       ├── railtie.rb                       # Auto-install middleware, subscribers
│       ├── engine.rb                        # Web UI (Rails engine)
│       └── cli.rb                           # Thor-based CLI
├── app/                                     # Engine views/controllers
│   ├── controllers/inspector/
│   └── views/inspector/
├── spec/
│   ├── inspector/
│   │   ├── recorder_spec.rb
│   │   ├── context_spec.rb
│   │   ├── subscribers/
│   │   ├── store/
│   │   └── formatters/
│   └── integration/
│       ├── sidekiq_spec.rb
│       └── rack_spec.rb
└── inspector.gemspec
```

### Why This Structure

- **Subscribers are isolated.** Adding support for a new library (e.g., `Typhoeus`, `gRPC`) means adding one file in `subscribers/`. Nothing else changes.
- **Stores are pluggable.** The interface is four methods. Adding a new backend is one file.
- **Formatters are separate from data.** The Trace/Span objects carry data. Formatters decide how to present it. Want a Slack formatter? Add one file.
- **The Railtie wires everything.** In a Rails app, `require 'inspector'` is all you need. The Railtie registers middleware, subscribes to notifications, and configures defaults based on `Rails.env`.

---

## Configuration

```ruby
# config/initializers/inspector.rb
Inspector.configure do |config|
  # ── Storage ──────────────────────────────────────────────────────────
  config.store = :sqlite                     # :sqlite | :postgresql | :memory
  config.sqlite_path = "tmp/inspector/inspector.db"

  # ── What to record ───────────────────────────────────────────────────
  config.recording_mode = :always            # :always | :selective | :off
  config.record_on_error = true              # buffer in memory, flush on exception
  config.record_jobs = :all                  # :all | :none | ["SpecificJob"]
  config.record_requests = :all              # :all | :none | ->(env) { ... }
  config.sample_rate = 1.0                   # 0.0 - 1.0, for production sampling

  # ── What to capture ──────────────────────────────────────────────────
  config.capture_sql_binds = true            # include bind parameters in SQL spans
  config.capture_http_headers = [:content_type, :authorization_type]
  config.capture_http_body = false           # careful with PII
  config.capture_redis_values = false        # just keys + commands by default

  # ── Source location capture ──────────────────────────────────────────
  #
  # This is the most expensive per-span operation (~5-25μs per span).
  # Controls how much of the call stack Inspector captures for each span.
  #
  config.source_mode = :full                 # :full | :shallow | :off
                                             #   :full    — up to source_depth app frames (best for debugging)
                                             #   :shallow — single nearest app frame (lower overhead)
                                             #   :off     — skip caller_locations entirely (fastest)
  config.source_filter = %w[app/ lib/]       # only keep frames whose path includes these prefixes
  config.source_depth = 3                    # max app frames to retain per span (only in :full mode)
  config.source_stack_limit = 50             # max raw stack frames to walk via caller_locations(0, N)
                                             # lower = faster, but may miss app frames in deep stacks

  # ── Span limits ──────────────────────────────────────────────────────
  #
  # Guards against unbounded memory growth for long-running or chatty jobs.
  #
  config.max_spans_per_trace = 1_000         # after this, new spans are counted but not stored
                                             # the trace footer shows "N additional spans truncated"
  config.span_overflow_strategy = :count     # :count — just increment a counter (default)
                                             # :sample — keep every Nth span after the cap
                                             # :categories — only drop low-priority categories (e.g. :cache)

  # ── Value truncation ─────────────────────────────────────────────────
  #
  # Large SQL bind params, HTTP bodies, and Redis values can spike memory.
  # These limits truncate individual values, not the span itself.
  #
  config.max_sql_bind_size = 1_024           # bytes — bind values larger than this are truncated
                                             # truncated values show: "[truncated, 48KB original]"
  config.max_http_body_size = 2_048          # bytes — for request/response bodies (when capture_http_body is true)
  config.max_redis_value_size = 512          # bytes — for Redis values (when capture_redis_values is true)
  config.max_span_detail_size = 4_096        # bytes — the main detail string (e.g. SQL query text)
                                             # protects against generated queries with huge IN clauses

  # ── Memory budget ────────────────────────────────────────────────────
  #
  # Hard ceiling on how much memory a single trace's in-memory buffer can use.
  # When exceeded, the trace is partially flushed to the store and the buffer is cleared.
  #
  config.max_trace_buffer_bytes = 5_242_880  # 5 MB — flush-to-store threshold
                                             # set to nil to disable (not recommended in production)

  # ── Retention ────────────────────────────────────────────────────────
  config.retention = 72.hours                # traces older than this are eligible for cleanup
  config.max_traces = 10_000                 # safety cap — oldest traces pruned when exceeded

  # ── Performance ──────────────────────────────────────────────────────
  config.async_store = true                  # write to store in a background thread
                                             # avoids blocking the job/request on storage I/O
end
```

### Environment Defaults

Inspector ships with sensible defaults per environment. Developers only need to override what they want to change.

| Setting                  | Development      | Test           | Production       |
|--------------------------|------------------|----------------|------------------|
| `recording_mode`         | `:always`        | `:off`         | `:selective`     |
| `store`                  | `:sqlite`        | `:memory`      | `:postgresql`    |
| `capture_sql_binds`      | `true`           | `true`         | `false`          |
| `source_mode`            | `:full`          | `:full`        | `:shallow`       |
| `source_depth`           | `3`              | `3`            | `1`              |
| `source_stack_limit`     | `50`             | `50`           | `30`             |
| `max_spans_per_trace`    | `1_000`          | `1_000`        | `500`            |
| `max_sql_bind_size`      | `4_096`          | `4_096`        | `512`            |
| `max_http_body_size`     | `8_192`          | `8_192`        | `1_024`          |
| `max_span_detail_size`   | `8_192`          | `8_192`        | `2_048`          |
| `max_trace_buffer_bytes` | `10 MB`          | `5 MB`         | `5 MB`           |
| `retention`              | `72.hours`       | N/A            | `24.hours`       |
| `record_on_error`        | `true`           | `false`        | `true`           |
| `async_store`            | `false`          | `false`        | `true`           |

---

## Performance Considerations

Inspector **must not** slow down the application meaningfully. Targets:

- **< 1ms overhead per trace** when recording (dominated by `caller_locations`)
- **Zero overhead** when not recording (context check is a thread-local read)
- **Memory-bounded** buffers (configurable via `max_spans_per_trace` and `max_trace_buffer_bytes`)

All performance-sensitive behavior is exposed as configuration. Developers can tune the trade-off between trace detail and overhead for their environment.

### How Each Configuration Lever Helps

1. **Context guard.** Every subscriber's first line: `return unless Inspector::Context.active?`. This is a single `Thread.current[]` read — effectively free. Combined with `recording_mode = :off`, the gem has zero runtime cost.

2. **`source_mode` controls the biggest per-span cost.** `caller_locations` dominates latency (~5-25μs per span depending on stack depth). Three modes give developers direct control:
   - `:full` — walks up to `source_stack_limit` frames (default 50), keeps `source_depth` app frames. Best for debugging.
   - `:shallow` — walks a smaller window, keeps only the nearest app frame. ~60% cheaper than `:full`.
   - `:off` — skips `caller_locations` entirely. Spans still record what happened and when, but not where in your code. Fastest option for production sampling where timing data matters more than source lines.

3. **Value truncation prevents memory spikes.** `max_sql_bind_size`, `max_http_body_size`, `max_redis_value_size`, and `max_span_detail_size` truncate large payloads at capture time. A TEXT column update with a 50KB body becomes a 1KB truncated value plus a size annotation. This is the single most important safety valve — without it, a single span can hold megabytes of string data.

4. **`max_spans_per_trace` bounds the span buffer.** After the cap, `span_overflow_strategy` determines behavior: count-only (cheapest), sampling (keep every Nth), or category-based dropping (keep SQL/HTTP, drop cache hits). The trace footer reports how many spans were truncated so the developer knows the trace is incomplete.

5. **`max_trace_buffer_bytes` is the hard memory ceiling.** When the in-memory buffer for a single trace exceeds this threshold, Inspector does a partial flush — serializes the buffered spans to the store and clears the buffer. The trace still appears as one unit when read back. This prevents long-running jobs (minutes, not milliseconds) from accumulating unbounded memory.

6. **`async_store` moves serialization off the hot path.** Completed traces are pushed to a thread-safe queue and serialized/written by a background thread. The job or request is never blocked by storage I/O. The momentary 2x memory spike from JSON serialization happens on the background thread, reducing GC pressure on the worker.

7. **Buffered record-on-error.** When `record_on_error` is true and `recording_mode` is `:selective`, Inspector buffers spans in memory during execution. If the execution succeeds and the job/request wasn't explicitly in the record list, the buffer is simply discarded — no serialization, no store write, minimal cost. If an exception occurs, the buffer is flushed. You get traces for every failure without paying the storage cost for successes.

---

## How Users Interact With Inspector (Workflow)

### Workflow 1: "This job failed, what happened?"

```
1. Job fails in Sidekiq
2. Developer sees error in Sidekiq UI / error tracker
3. $ bundle exec inspector search --class=SendInvoiceJob --status=error --since=1h
4. $ bundle exec inspector show tr_abc123
5. Sees the full timeline with source locations
6. Goes directly to the line that caused the issue
```

### Workflow 2: "This job ran but produced wrong data"

```
1. Developer notices incorrect data in the database
2. $ bundle exec inspector search --class=SyncInventoryJob --since=2h
3. $ bundle exec inspector show tr_def456
4. Sees that an UPDATE query had unexpected WHERE clause
5. Source location points to app/services/inventory_sync.rb:89
6. Opens file, sees the bug immediately
```

### Workflow 3: "This used to work, now it doesn't"

```
1. $ bundle exec inspector search --class=SendInvoiceJob --status=success --limit=1
2. $ bundle exec inspector search --class=SendInvoiceJob --status=error --limit=1
3. $ bundle exec inspector diff tr_good tr_bad
4. Diff shows: HTTP call to billing service now returns 503
5. Root cause: billing service is down, not a code bug
```

### Workflow 4: "I'm writing a new service, does it do what I think?"

```ruby
# In development, after writing new code:
trace = Inspector.trace("manual test") do
  OrderService.new(user: user, cart: cart).checkout
end

puts trace.to_timeline
# See every query, HTTP call, enqueued job — verify it's correct
# before it ever hits staging
```

### Workflow 5: "I want to assert side effects in a test"

```ruby
RSpec.describe OrderService do
  it "charges the card and enqueues receipt email" do
    trace = Inspector.trace("test") do
      described_class.new(user: user, cart: cart).checkout
    end

    expect(trace.spans.http.count).to eq(1)
    expect(trace.spans.http.first.detail).to match(/payments.stripe.com/)
    expect(trace.spans.category(:enqueue).map(&:detail)).to include(/SendReceiptEmailJob/)
  end
end
```

---

## Build Order (Recommended Phases)

### Phase 1 — Core Recording (the MVP)

Ship a gem that records traces for Sidekiq jobs and Rack requests, stores them in SQLite, and prints them via CLI.

Deliverables:
- `Trace`, `Span`, `Context` data structures
- `Recorder` orchestrator
- `ActiveRecord` subscriber (SQL only — this covers 80% of debugging)
- Sidekiq middleware
- Rack middleware
- SQLite store
- CLI: `inspector list`, `inspector show <id>`
- Railtie for auto-installation
- `Inspector.trace { }` for manual usage

This alone is useful. A developer can install the gem, run their app, and inspect any job or request.

### Phase 2 — Richer Capture

- HTTP subscriber (Net::HTTP, Faraday)
- Redis subscriber
- Cache subscriber
- Mailer subscriber
- Active Job enqueue subscriber
- `Inspector.span`, `Inspector.snapshot`, `Inspector.tag`
- CLI: `inspector search`, `inspector show --only=sql`

### Phase 3 — Diff & Correlation

- Trace diffing algorithm and `inspector diff` command
- Correlation ID propagation (request → job → child job)
- `inspector trace <id> --follow` for causal chains

### Phase 4 — Web UI & Polish

- Rails Engine with Hotwire-powered UI
- PostgreSQL store backend
- Retention & cleanup job
- Async store writes
- Production sampling/selective recording

### Phase 5 — Advanced

- Test assertions API (`expect(trace.spans...)`)
- Export to OpenTelemetry format
- VS Code extension (click span → jump to source location)
- Replay mode (from initial design doc)

---

## What Inspector Is Not

- **Not an APM.** No dashboards, no percentile charts, no alerting. Inspector is for *understanding a single execution*, not monitoring aggregate system health.
- **Not a logger.** It doesn't capture arbitrary log messages (though you can add custom spans). It captures structured I/O events.
- **Not a profiler.** It doesn't measure CPU time or memory allocation. It measures wall-clock time of I/O operations.
- **Not a distributed tracer.** It doesn't follow requests across microservices (though it could export to OpenTelemetry for that). It stays within one Ruby process.

It is a **post-mortem debugger for units of work.** That's the focus. That's the value.

---

## Open Questions

1. **Gem name**: `inspector` may conflict. Alternatives: `dontbugme`, `exec_inspector`, `trace_inspector`, `job_scope`. Worth checking RubyGems.
2. **SQL bind param sanitization**: In production, bind params may contain PII. Need a sanitization/redaction layer.
3. **ActiveRecord query source comments**: Rails 7+ has `Marginalia`-style query tagging. Should Inspector leverage this or capture its own source location?
4. **Span nesting**: Should transactions create a parent span that nests child queries? Adds complexity but improves readability.
5. **Thread safety for concurrent HTTP calls**: Jobs using `Parallel` or `concurrent-ruby` may make HTTP calls from multiple threads. Need to handle span collection across threads within one trace.
