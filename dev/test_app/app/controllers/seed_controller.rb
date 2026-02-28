# frozen_string_literal: true

class SeedController < ApplicationController
  def index
    create_dummy_traces
    redirect_to '/inspector?seeded=1'
  end

  private

  def create_dummy_traces
    store = Dontbugme.store
    return unless store

    [
      create_dummy_request_trace,
      create_dummy_sidekiq_trace,
      create_dummy_sidekiq_error_trace,
      create_dummy_custom_trace
    ].each { |trace| store.save_trace(trace) }
  end

  def create_dummy_request_trace
    base = Time.now.utc - 300
    trace = Dontbugme::Trace.from_h(
      id: "tr_#{SecureRandom.hex(6)}",
      kind: :request,
      identifier: 'GET /api/users/42',
      status: :success,
      started_at: base.iso8601(3),
      duration_ms: 245.5,
      correlation_id: "corr_#{SecureRandom.hex(8)}",
      metadata: { request_id: SecureRandom.uuid, method: 'GET', path: '/api/users/42' },
      spans: [
        sql_span(0, 12.3, 'SELECT * FROM users WHERE id = ?', binds: [42]),
        sql_span(15, 8.2, 'SELECT * FROM orders WHERE user_id = ?', binds: [42]),
        http_span(28, 156.4, 'GET https://api.stripe.com/v1/customers'),
        redis_span(190, 2.1, 'GET', 'user:42:cache'),
        cache_span(195, 0.8, 'read', 'views/users/42'),
        mailer_span(200, 45.2, 'UserMailer#welcome'),
        enqueue_span(248, 1.2, 'SendWelcomeEmailJob')
      ],
      truncated_spans_count: 0
    )
    trace
  end

  def create_dummy_sidekiq_trace
    base = Time.now.utc - 180
    trace = Dontbugme::Trace.from_h(
      id: "tr_#{SecureRandom.hex(6)}",
      kind: :sidekiq,
      identifier: 'ProcessOrderJob (jid=abc123)',
      status: :success,
      started_at: base.iso8601(3),
      duration_ms: 892.3,
      correlation_id: "corr_#{SecureRandom.hex(8)}",
      metadata: { jid: 'abc123', queue: 'default', correlation_id: "corr_#{SecureRandom.hex(8)}" },
      spans: [
        sql_span(0, 5.2, 'BEGIN'),
        sql_span(8, 45.1, 'UPDATE orders SET status = ? WHERE id = ?', binds: ['completed', 1001]),
        sql_span(58, 12.3, 'INSERT INTO order_events (order_id, event) VALUES (?, ?)', binds: [1001, 'completed']),
        http_span(75, 234.5, 'POST https://api.shipping.com/v1/labels'),
        redis_span(315, 1.2, 'SET', 'order:1001:shipped'),
        cache_span(320, 0.5, 'delete', 'order:1001:details'),
        sql_span(325, 8.1, 'COMMIT'),
        custom_span(340, 15.2, 'Calculate tax'),
        snapshot_span(360, { order_id: 1001, total: 99.99, tax: 8.50 })
      ],
      truncated_spans_count: 0
    )
    trace
  end

  def create_dummy_sidekiq_error_trace
    base = Time.now.utc - 60
    trace = Dontbugme::Trace.from_h(
      id: "tr_#{SecureRandom.hex(6)}",
      kind: :sidekiq,
      identifier: 'SendInvoiceJob (jid=err456)',
      status: :error,
      started_at: base.iso8601(3),
      duration_ms: 125.3,
      correlation_id: "corr_#{SecureRandom.hex(8)}",
      metadata: { jid: 'err456', queue: 'default' },
      error: {
        class: 'Net::OpenTimeout',
        message: 'execution expired',
        backtrace: [
          'app/jobs/send_invoice_job.rb:15:in `perform`',
          'app/services/invoice_service.rb:42:in `deliver`',
          'gems/net-http/lib/net/http.rb:987:in `connect`'
        ]
      },
      spans: [
        sql_span(0, 3.1, 'SELECT * FROM invoices WHERE id = ?', binds: [999]),
        http_span(10, 120.0, 'POST https://api.invoicing.com/upload', status: nil, error: 'execution expired')
      ],
      truncated_spans_count: 0
    )
    trace
  end

  def create_dummy_custom_trace
    base = Time.now.utc - 30
    trace = Dontbugme::Trace.from_h(
      id: "tr_#{SecureRandom.hex(6)}",
      kind: :custom,
      identifier: 'checkout flow',
      status: :success,
      started_at: base.iso8601(3),
      duration_ms: 156.8,
      metadata: { customer_tier: 'enterprise' },
      spans: [
        custom_span(0, 12.5, 'Validate cart'),
        custom_span(15, 8.2, 'Calculate tax'),
        snapshot_span(25, { user_id: 42, cart_total: 199.99, items: 3 }),
        sql_span(30, 45.2, 'INSERT INTO orders (user_id, total, created_at) VALUES (?, ?, ?)', binds: [42, 199.99, Time.now]),
        redis_span(80, 2.1, 'DEL', 'cart:42'),
        cache_span(85, 0.3, 'write', 'user:42:last_order')
      ],
      truncated_spans_count: 0
    )
    trace
  end

  def sql_span(offset, duration, sql, binds: [])
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :sql,
      operation: sql.strip.upcase.start_with?('SELECT') ? 'SELECT' : (sql.strip.upcase.start_with?('INSERT') ? 'INSERT' : 'OTHER'),
      detail: sql,
      payload: { name: 'SQL', binds: binds },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/models/order.rb:42 in `create_from_cart`'
    }
  end

  def http_span(offset, duration, url, status: 200, error: nil)
    payload = { method: url.split.first, url: url, status: status }
    payload[:response_body] = '{"id":"cus_123","email":"user@example.com"}' if status && !error
    payload[:error] = error if error
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :http,
      operation: url.split.first,
      detail: url,
      payload: payload,
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/services/shipping_service.rb:28 in `create_label`'
    }
  end

  def redis_span(offset, duration, cmd, *args)
    output = case cmd
             when 'GET' then '"{\"user_id\":42,\"name\":\"John\"}"'
             when 'SET' then '"OK"'
             when 'DEL' then '1'
             else 'nil'
             end
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :redis,
      operation: cmd,
      detail: [cmd, *args].join(' '),
      payload: { command: cmd, args: args, output: output },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/models/order.rb:55 in `clear_cart_cache`'
    }
  end

  def cache_span(offset, duration, op, key)
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :cache,
      operation: op,
      detail: "cache #{op} #{key}",
      payload: { key: key, hit: op == 'read' },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/controllers/application_controller.rb:12 in `cache_user`'
    }
  end

  def mailer_span(offset, duration, mailer_action)
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :mailer,
      operation: 'deliver',
      detail: mailer_action,
      payload: { mailer: mailer_action.split('#').first, action: mailer_action.split('#').last, to: 'user@example.com', subject: 'Welcome!' },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/mailers/user_mailer.rb:8 in `welcome`'
    }
  end

  def enqueue_span(offset, duration, job_class)
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :enqueue,
      operation: 'ENQUEUE',
      detail: "ENQUEUE #{job_class}",
      payload: { job: job_class, queue: 'default', args: ['user_42'] },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/controllers/users_controller.rb:25 in `create`'
    }
  end

  def custom_span(offset, duration, name)
    output = case name
             when 'Calculate tax' then '8.50'
             when 'Validate cart' then 'true'
             else '{ success: true }'
             end
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :custom,
      operation: 'span',
      detail: name,
      payload: { output: output },
      started_at: offset.to_f,
      duration_ms: duration,
      source: 'app/services/checkout_service.rb:33 in `process`'
    }
  end

  def snapshot_span(offset, data)
    {
      id: "sp_#{SecureRandom.hex(4)}",
      category: :snapshot,
      operation: 'snapshot',
      detail: 'snapshot',
      payload: data,
      started_at: offset.to_f,
      duration_ms: 0,
      source: nil
    }
  end
end
