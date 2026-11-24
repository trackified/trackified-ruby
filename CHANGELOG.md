# Changelog

## 0.2.0

All additive; code written for 0.1 keeps working.

- T-1/T-3: `base_url:` accepts `https://api.trackified.net` or `https://api.trackified.net/v1`, with or without a
  trailing slash; one trailing `/v1` is stripped.
- T-2: `usage.get` keeps calling `/v1/account/usage` (`/v1/usage` is an API alias).
- T-4: `client.health` (`GET /v1/health`).
- T-5: `carriers.resolve(name)` returns a `CarrierResolution` (`carrier`, `name`, `confidence`, `matched`) or nil.
  `Carrier#aliases`; `Carrier#display_name` reads `display_name` or `displayName`.
- T-6: `Event#tracking` (and `Trackified::Webhook.tracking_of(event)`, `client.webhooks.tracking_of`) returns the
  Tracking for any event type; `Event#previous_status` / `#current_status` for `tracking.status_changed`.
- T-7: `TrackingEvent#date` is deprecated, removed after 2027-06-01. Documented what a zoneless `occurred_at` means.
- T-8: documented that `Tracking#events` is newest first (guaranteed by the API).
- T-9: `WebhookSignature.verify_detailed` returns `valid` and `reason` (`missing`, `malformed`, `timestamp`,
  `mismatch`); `SignatureVerificationError#reason`.
- T-10: signatures with several `v1=` values verify if any matches; verification accepts an array of secrets;
  `webhooks.rotate_secret(id, expires_in_hours:)`.
- T-11: `webhooks.update(id, url:, event_types:, enabled:)`.
- T-12: `QuotaExceededError` (402) and `ConflictError` (409, not retried), both subclasses of `APIError` as before;
  `ConnectionError#code` is `"timeout"` or `"connection"`.
- T-13: `on_request:` / `on_response:` client hooks, called once per attempt; exceptions they raise are ignored.

## 0.1.1

- First published release (0.1.0 was tagged but never built).

## 0.1.0

- First release: every Trackified API operation (trackings, carriers, webhooks, webhook deliveries, API keys,
  usage), auto-pagination, retries with backoff, typed errors, webhook signature verification, RBS signatures.
