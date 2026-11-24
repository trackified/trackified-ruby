# frozen_string_literal: true

require "erb"

module Trackified
  # API resources, reached through Client#trackings, #carriers, etc.
  module Resources
    # @api private
    class Base
      def initialize(client)
        @client = client
      end

      private

      def req(...) = @client.request(...)
      def esc(id) = ERB::Util.url_encode(id.to_s)

      def page(path, klass, query)
        fetch = ->(offset) { page(path, klass, query.merge(offset: offset)) }
        Page.new(req(:get, path, query: query), klass, &fetch)
      end
    end

    # /v1/trackings
    class Trackings < Base
      # @return [Tracking]
      def create(tracking_number:, carrier: nil, custom_id: nil, customer_email: nil, idempotency_key: nil)
        body = { tracking_number: tracking_number, carrier: carrier, custom_id: custom_id,
                 customer_email: customer_email }.compact
        Tracking.new(req(:post, "/v1/trackings", body: body, idempotency_key: idempotency_key))
      end

      # One page. Enumerate the result (each / auto_paging_each) to walk every page.
      # @return [Page<Tracking>]
      def list(limit: nil, offset: nil, status: nil, carrier: nil, custom_id: nil, tracking_number: nil)
        page("/v1/trackings", Tracking, { limit: limit, offset: offset, status: status, carrier: carrier,
                                          custom_id: custom_id, tracking_number: tracking_number }.compact)
      end

      # @param trackings [Array<Hash>] each {tracking_number:, carrier:, custom_id:, customer_email:}
      # @return [Array<Hash>] per item {"ok", "tracking" => Tracking, "error"}
      def bulk_create(trackings, idempotency_key: nil)
        res = req(:post, "/v1/trackings/bulk", body: { trackings: trackings }, idempotency_key: idempotency_key)
        (res["data"] || []).map { |r| r["tracking"] ? r.merge("tracking" => Tracking.new(r["tracking"])) : r }
      end

      # @return [Tracking]
      def get(id) = Tracking.new(req(:get, "/v1/trackings/#{esc(id)}"))

      # @return [Tracking]
      def update(id, carrier: nil, custom_id: nil, customer_email: nil)
        body = { carrier: carrier, custom_id: custom_id, customer_email: customer_email }.compact
        Tracking.new(req(:put, "/v1/trackings/#{esc(id)}", body: body))
      end

      # Stops tracking. @return [Hash] {"deleted" => true, "id" => ...}
      def delete(id) = req(:delete, "/v1/trackings/#{esc(id)}")

      # Queues a fresh scrape. @return [Hash] {"queued", "tracking" => Tracking}
      def retrack(id)
        res = req(:post, "/v1/trackings/#{esc(id)}/retrack")
        res && res["tracking"] ? res.merge("tracking" => Tracking.new(res["tracking"])) : res
      end
    end

    # /v1/carriers
    class Carriers < Base
      # @return [Page<Carrier>]
      def list(limit: nil, offset: nil) = page("/v1/carriers", Carrier, { limit: limit, offset: offset }.compact)

      # @return [Carrier]
      def get(id) = Carrier.new(req(:get, "/v1/carriers/#{esc(id)}"))

      # @return [Array<CarrierCandidate>] most likely first
      def detect(tracking_number)
        res = req(:get, "/v1/carriers/detect", query: { number: tracking_number })
        (res["candidates"] || []).map { |c| CarrierCandidate.new(c) }
      end

      # Searches every known carrier, including unsupported ones.
      # @param support [String, nil] "scraper", "api" or "unsupported"
      # @return [Hash] {"total", "counts", "data" => [Hash]}
      def catalog(q: nil, support: nil, limit: nil)
        req(:get, "/v1/carriers/catalog", query: { q: q, support: support, limit: limit })
      end

      # Per-carrier validation status. @return [Hash] {"counts", "values"}
      def status = req(:get, "/v1/carriers/status")
    end

    # /v1/webhooks, plus signature verification.
    class Webhooks < Base
      # @return [Webhook] includes #secret (only shown once)
      def create(url:, event_types: nil)
        Webhook.new(req(:post, "/v1/webhooks", body: { url: url, event_types: event_types }.compact))
      end

      # @return [Page<Webhook>]
      def list(limit: nil, offset: nil) = page("/v1/webhooks", Webhook, { limit: limit, offset: offset }.compact)

      # @return [nil]
      def delete(id)
        req(:delete, "/v1/webhooks/#{esc(id)}")
        nil
      end

      # Sends a signed sample event. @return [Hash] {"signature", "body"}
      def test(id) = req(:post, "/v1/webhooks/#{esc(id)}/test")

      # @see Trackified::WebhookSignature.verify
      def verify(raw_body, header, secret, tolerance: WebhookSignature::DEFAULT_TOLERANCE)
        WebhookSignature.verify(raw_body, header, secret, tolerance: tolerance)
      end

      # @see Trackified::WebhookSignature.construct_event
      def construct_event(raw_body, header, secret, tolerance: WebhookSignature::DEFAULT_TOLERANCE)
        WebhookSignature.construct_event(raw_body, header, secret, tolerance: tolerance)
      end
    end

    # /v1/webhook-deliveries
    class WebhookDeliveries < Base
      # @return [Page<WebhookDelivery>] newest first
      def list(limit: nil, offset: nil)
        page("/v1/webhook-deliveries", WebhookDelivery, { limit: limit, offset: offset }.compact)
      end
    end

    # /v1/account/api-keys
    class ApiKeys < Base
      # @param mode [String, nil] "test" or "live"
      # @return [ApiKey] includes #token (only shown once)
      def create(name: nil, mode: nil, scopes: nil)
        ApiKey.new(req(:post, "/v1/account/api-keys", body: { name: name, mode: mode, scopes: scopes }.compact))
      end

      # @return [Page<ApiKey>]
      def list(limit: nil, offset: nil)
        page("/v1/account/api-keys", ApiKey, { limit: limit, offset: offset }.compact)
      end

      # @return [nil]
      def revoke(id)
        req(:delete, "/v1/account/api-keys/#{esc(id)}")
        nil
      end
    end

    # /v1/account/usage
    class Usage < Base
      # @return [Trackified::Usage]
      def get = Trackified::Usage.new(req(:get, "/v1/account/usage"))
    end
  end
end
