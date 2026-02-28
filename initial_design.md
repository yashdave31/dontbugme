Inspector

Inspector is a developer tool that reconstructs the full execution story of a single Sidekiq job.

Given a job_id, it shows exactly what happened during that job:

What database queries ran

What rows were inserted/updated/deleted

What HTTP services were called

What Redis operations occurred

What exceptions were raised

How long each step took

The precise execution timeline

It turns a Sidekiq job into a deterministic, inspectable trace.

The Problem It Solves

When a Sidekiq job fails — or worse, behaves incorrectly without failing — it’s difficult to answer:

What exactly happened inside that job?

Which external services were touched?

What database state was changed?

In what order did events occur?

What was the blast radius?

Logs are noisy.
Tracing tools focus on request-level spans.
Database logs lack context.

There’s no unified, job-scoped narrative.

Inspector provides that narrative.

How It Works (Conceptually)

When a Sidekiq job starts, Inspector:

Attaches to the job’s jid

Records structured events throughout execution

Captures:

SQL queries (via ActiveSupport notifications)

HTTP calls (via client instrumentation)

Redis operations

Transaction boundaries

Exceptions

Stores events in an append-only log

Reconstructs a causally ordered timeline

Each job becomes a self-contained execution trace.

What Using It Feels Like
Recording happens automatically.

You run your app normally.

Inspect a job:
Inspector inspect --job-id=abc123

Output:

Job: SendInvoiceJob (jid=abc123)
Duration: 65ms

[0ms]   Job started
[5ms]   SELECT users WHERE id=42
[8ms]   BEGIN TRANSACTION
[10ms]  INSERT invoices (...)
[25ms]  HTTP POST https://billing.internal/charge
[50ms]  UPDATE invoices SET status='paid'
[60ms]  COMMIT
[65ms]  Job finished

Optionally:

Inspector inspect --job-id=abc123 --json
Inspector inspect --job-id=abc123 --graph
What It Should Feel Like

Using Inspector should feel:

Like git log for a Sidekiq job

Like a flight recorder for background work

Like a microscope for side effects

Calm, deterministic, structured

Not noisy.
Not opinionated.
Not magical.

Just a precise reconstruction of reality.

Design Principles

Job-scoped (never global)

Append-only event log

Thread-safe

Minimal performance overhead

Storage-agnostic (file / Postgres / SQLite)

No external SaaS dependency

Works locally first

Optional Future Direction

Replay mode:

Inspector replay --job-id=abc123

Stub external HTTP calls

Reproduce DB responses

Freeze time

Step through execution

But inspect-first is the core value.