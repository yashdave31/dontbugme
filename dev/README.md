# Dontbugme Dev / Test App

Minimal Rails app to preview the Dontbugme Web UI with dummy data.

## Quick Start

From the gem root:

```bash
./script/dev_ui
```

Or manually:

```bash
cd dev/test_app
bundle install
bundle exec rackup config.ru -p 3000
```

Then open:

1. **http://localhost:3000/seed** — Creates 4 dummy traces with all span types, then redirects to the UI
2. **http://localhost:3000/inspector** — View traces directly

## Dummy Data

The `/seed` endpoint creates:

- **Request trace** — GET /api/users/42 with SQL, HTTP, Redis, Cache, Mailer, Enqueue spans
- **Sidekiq trace** — ProcessOrderJob with SQL, HTTP, Redis, Cache, Custom, Snapshot spans
- **Error trace** — SendInvoiceJob that failed with Net::OpenTimeout
- **Custom trace** — checkout flow with Custom, Snapshot, SQL, Redis, Cache spans

Span categories: SQL, HTTP, Redis, Cache, Mailer, Enqueue, Custom, Snapshot.
