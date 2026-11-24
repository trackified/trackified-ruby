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
tracking.events.each { |e| puts "#{e.occurred_at} #{e.status} #{e.description}" }

# List one page...
page = client.trackings.list(limit: 50, status: Trackified::TrackingStatus::DELIVERED)
page.data        # this page's trackings
page.pagination  # {"limit"=>50, "offset"=>0, "total"=>123}

# ...or iterate every tracking across all pages
client.trackings.list.each { |t| puts t.tracking_number }
```

Other resources: `client.carriers` (`list`, `get`, `detect`, `catalog`, `status`), `client.webhooks`
(`create`, `list`, `delete`, `test`), `client.webhook_deliveries.list`, `client.api_keys` (`create`, `list`,
`revoke`) and `client.usage.get`. Trackings also have `bulk_create`, `update`, `delete` and `retrack`.

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
  when Trackified::WebhookEventType::TRACKING_DELIVERED then OrderMailer.delivered(event.data["id"]).deliver_later
  end
  head :ok
rescue Trackified::SignatureVerificationError
  head :bad_request
end
```

`Trackified::WebhookSignature.verify(raw_body, header, secret, tolerance: 300)` returns a boolean instead.
Both are also available as `client.webhooks.verify` / `client.webhooks.construct_event`.

## Configuration

| Option | Default | Env |
| --- | --- | --- |
| `api_key:` | required | `TRACKIFIED_API_KEY` |
| `base_url:` | `https://api.trackified.net` | `TRACKIFIED_BASE_URL` |
| `timeout:` | 30 seconds | |
| `max_retries:` | 2 | |

Network errors, 408, 429 (honouring `retry-after`) and 5xx are retried with exponential backoff and jitter.
Other 4xx are never retried.

## Errors

All errors inherit from `Trackified::TrackifiedError` and expose `status`, `code`, `message` and `request_id`:
`AuthenticationError` (401), `PermissionError` (403), `NotFoundError` (404), `ValidationError` (400/422),
`RateLimitError` (429, with `retry_after`), `APIError` (5xx and other statuses), `ConnectionError` (network).

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
