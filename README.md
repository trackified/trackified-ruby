# Trackified Ruby

[![CI](https://github.com/trackified/trackified-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/trackified/trackified-ruby/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/trackified)](https://rubygems.org/gems/trackified)

Official Ruby client for the [Trackified](https://trackified.net) parcel-tracking API. Ruby 3.1+, no runtime
dependencies (stdlib `Net::HTTP`). Works in Rails, Sinatra and plain Ruby.

Full API docs: https://forumulate.com/p/trackified/docs

## Install

```ruby
# Gemfile
gem "trackified"
```

## Quickstart

```ruby
require "trackified"

client = Trackified::Client.new(api_key: ENV["TRACKIFIED_API_KEY"]) # or just Trackified::Client.new

# Create a tracking (an Idempotency-Key is generated for you and reused across retries)
tracking = client.trackings.create(tracking_number: "9434650110837017316201", carrier: "usps", custom_id: "order-1001")

# Get it
tracking = client.trackings.get(tracking.id)
puts tracking.status # => "in_transit" (see Trackified::TrackingStatus)
tracking.events.each { |e| puts "#{e.occurred_at} #{e.status} #{e.description}" } # newest first

# List one page...
page = client.trackings.list(limit: 50, status: Trackified::TrackingStatus::DELIVERED)
page.data        # this page's trackings
page.pagination  # {"limit"=>50, "offset"=>0, "total"=>123}

# ...or iterate every tracking across all pages
client.trackings.list.each { |t| puts t.tracking_number }
```

Other resources: `client.carriers` (`list`, `get`, `resolve`, `detect`, `catalog`, `status`), `client.webhooks`
(`create`, `list`, `update`, `rotate_secret`, `delete`, `test`), `client.webhook_deliveries.list`,
`client.api_keys` (`create`, `list`, `revoke`), `client.usage.get` (calls `GET /v1/account/usage`) and
`client.health` (`GET /v1/health`, returns `{"status" => "ok"}`). Trackings also have `bulk_create`, `update`,
`delete` and `retrack`.

### Events and times

`tracking.events` is **newest first**: sorted by `occurred_at` descending, guaranteed by the API (undated events keep
their carrier position after the dated ones). An `occurred_at` without an offset is the local time where the scan
happened; when the carrier gives an offset it is included and `time_zone_known` is true. `event.date` is deprecated:
it is sent until 2027-06-01 and removed after that.

### Resolve a carrier name

```ruby
r = client.carriers.resolve("USPS Priority Mail") # also "dhl_express", "royal-mail", "Correos de España"
r&.carrier    # => "usps" (nil result when no carrier we serve matches)
r&.confidence # => 0.97
r&.matched    # => "alias" ("id", "alias", "name", "provider_slug" or "prefix")
```

`trackings.create(carrier:)` accepts the same free text and stores our id. Carriers also expose `aliases`.

### Update a webhook

```ruby
client.webhooks.update("wh_123", enabled: false)                 # or url:, event_types:
client.webhooks.update("wh_123", event_types: ["tracking.delivered"])
```

## Verify a webhook

Trackified signs every delivery with `x-tracking-signature: t=<unix seconds>,v1=<hex HMAC-SHA256>`. Verify it
against the **raw** request body ([guide](https://trackified.net/developers/webhook-signing)):

```ruby
# Rails controller
def trackified
  event = Trackified::WebhookSignature.construct_event(
    request.raw_post,
    request.headers["x-tracking-signature"],
    ENV.fetch("TRACKIFIED_WEBHOOK_SECRET")
  )
  case event.type
  when Trackified::WebhookEventType::TRACKING_DELIVERED then OrderMailer.delivered(event.tracking.id).deliver_later
  when Trackified::WebhookEventType::TRACKING_STATUS_CHANGED
    Rails.logger.info("#{event.tracking.id}: #{event.previous_status} -> #{event.current_status}")
  end
  head :ok
rescue Trackified::SignatureVerificationError
  head :bad_request
end
```

`event.data` is `{"tracking", "previous_status", "current_status"}` for `tracking.status_changed` and the tracking
itself for every other type. `event.tracking` (or `Trackified::Webhook.tracking_of(event)`) returns the `Tracking`
for any type.

`Trackified::WebhookSignature.verify(raw_body, header, secret, tolerance: 300)` returns a boolean instead.
`verify_detailed` says why it failed:

```ruby
result = Trackified::WebhookSignature.verify_detailed(raw_body, header, secret)
result.valid? # => false
result.reason # => "missing" | "malformed" | "timestamp" | "mismatch"
```

`SignatureVerificationError#reason` carries the same value. All of these are also on `client.webhooks`.

### Rotate a webhook secret

```ruby
webhook = client.webhooks.rotate_secret("wh_123", expires_in_hours: 24) # 0..168, default 24; 0 drops the old one now
webhook.secret                      # the new secret, shown once
webhook.previous_secret_expires_at  # until then, deliveries carry two signatures
```

During the window the header is `t=...,v1=<new>,v1=<old>` and a delivery is valid if any `v1` matches, so both the
old and the new secret verify. To switch without downtime, verify with both while you deploy the new one:

```ruby
Trackified::WebhookSignature.construct_event(raw_body, header, [new_secret, old_secret])
```

## Configuration

| Option | Default | Env |
| --- | --- | --- |
| `api_key:` | required | `TRACKIFIED_API_KEY` |
| `base_url:` | `https://api.trackified.net` | `TRACKIFIED_BASE_URL` |
| `timeout:` | 30 seconds | |
| `max_retries:` | 2 | |
| `on_request:` | none | |
| `on_response:` | none | |

`base_url:` may include `/v1` (`https://api.trackified.net/v1`) or not, with or without a trailing slash.

Network errors, 408, 429 (honouring `retry-after`) and 5xx are retried with exponential backoff and jitter.
Other 4xx are never retried.

### Hooks

```ruby
client = Trackified::Client.new(
  on_request: ->(r) { Rails.logger.debug("#{r[:method]} #{r[:url]} attempt #{r[:attempt]}") },
  on_response: lambda { |r|
    StatsD.timing("trackified.request", r[:duration_ms], tags: ["status:#{r[:status]}"])
  }
)
```

`on_request` gets `{method:, url:, attempt:, idempotency_key:}`; `on_response` gets `{method:, url:, attempt:,
status:, request_id:, idempotent_replayed:, duration_ms:, error:}`. Each is called once per attempt (`attempt` starts at
1). `error` is the typed error when the status is 400 or more, or a `ConnectionError` (with `status` nil) when the
connection failed. Exceptions raised in a hook are ignored and never break the request.

## Errors

All errors inherit from `Trackified::TrackifiedError` and expose `status`, `code`, `message` and `request_id`:
`AuthenticationError` (401), `PermissionError` (403), `NotFoundError` (404), `ValidationError` (400/422),
`QuotaExceededError` (402, code `quota_exceeded`), `ConflictError` (409, e.g. `idempotency_in_progress`; not retried),
`RateLimitError` (429, with `retry_after`), `APIError` (5xx and other statuses; also the parent of
`QuotaExceededError` and `ConflictError`), `ConnectionError` (network, with `code` `"timeout"` or `"connection"`).

After a timeout the outcome is **unknown**: the API may have done the work. Retry with the same idempotency key;
the SDK does this automatically for its own retries, and you can pass `idempotency_key:` to `trackings.create` /
`bulk_create` to carry it across your own retries.

```ruby
begin
  client.trackings.get("trk_missing")
rescue Trackified::NotFoundError => e
  warn "#{e.code}: #{e.message} (request #{e.request_id})"
end
```

## Types

RBS signatures ship in `sig/`. Models keep every field the API returns: use the typed readers, or `model["field"]`
and `model.to_h` for anything else.

## License

MIT
