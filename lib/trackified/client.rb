# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "securerandom"
require "uri"

module Trackified
  # Entry point.
  #
  #   client = Trackified::Client.new(api_key: "tk_test_...")
  #   client.trackings.create(tracking_number: "9434650110837017316201", carrier: "usps")
  class Client
    DEFAULT_BASE_URL = "https://api.trackified.net"
    RETRYABLE_STATUSES = [408, 429].freeze
    MAX_BACKOFF = 8.0
    NETWORK_ERRORS = [
      IOError, EOFError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError,
      Net::HTTPBadResponse
    ].freeze

    attr_reader :base_url, :timeout, :max_retries,
                :trackings, :carriers, :webhooks, :webhook_deliveries, :api_keys, :usage

    # @param api_key [String, nil] falls back to ENV["TRACKIFIED_API_KEY"]
    # @param base_url [String, nil] falls back to ENV["TRACKIFIED_BASE_URL"], then the production API
    # @param timeout [Numeric] seconds, per attempt
    # @param max_retries [Integer] retries after the first attempt
    def initialize(api_key: nil, base_url: nil, timeout: 30, max_retries: 2)
      @api_key = api_key || ENV.fetch("TRACKIFIED_API_KEY", nil)
      if @api_key.nil? || @api_key.empty?
        raise AuthenticationError, "No API key. Pass api_key: or set TRACKIFIED_API_KEY."
      end

      @base_url = (base_url || ENV.fetch("TRACKIFIED_BASE_URL", nil) || DEFAULT_BASE_URL).chomp("/")
      @timeout = timeout
      @max_retries = max_retries
      @trackings = Resources::Trackings.new(self)
      @carriers = Resources::Carriers.new(self)
      @webhooks = Resources::Webhooks.new(self)
      @webhook_deliveries = Resources::WebhookDeliveries.new(self)
      @api_keys = Resources::ApiKeys.new(self)
      @usage = Resources::Usage.new(self)
    end

    def inspect = "#<Trackified::Client base_url=#{@base_url.inspect}>"

    # Sends a request and returns the parsed JSON body (nil when empty).
    # @api private
    def request(method, path, query: nil, body: nil, idempotency_key: nil)
      uri = URI("#{@base_url}#{path}")
      query = query&.compact
      uri.query = URI.encode_www_form(query) if query && !query.empty?
      idempotency_key ||= SecureRandom.uuid if method == :post && body
      attempt = 0
      loop do
        begin
          res = perform(method, uri, body, idempotency_key)
        rescue *NETWORK_ERRORS => e
          raise ConnectionError, "#{e.class}: #{e.message}" if attempt >= @max_retries

          sleep(backoff(attempt, nil))
          attempt += 1
          next
        end
        status = res.code.to_i
        return parse(res.body) if status < 300

        err = build_error(status, res)
        raise err unless retryable?(status) && attempt < @max_retries

        sleep(backoff(attempt, err.is_a?(RateLimitError) ? err.retry_after : nil))
        attempt += 1
      end
    end

    private

    def perform(method, uri, body, idempotency_key)
      req = Net::HTTPGenericRequest.new(method.to_s.upcase, !body.nil?, true, uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"] = "application/json"
      req["User-Agent"] = "trackified-ruby/#{VERSION}"
      req["Idempotency-Key"] = idempotency_key if idempotency_key
      unless body.nil?
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)
      end
      opts = { use_ssl: uri.scheme == "https", open_timeout: @timeout, read_timeout: @timeout, write_timeout: @timeout }
      Net::HTTP.start(uri.host, uri.port, **opts) { |http| http.request(req) }
    end

    def parse(raw)
      raw.nil? || raw.strip.empty? ? nil : JSON.parse(raw)
    end

    def retryable?(status) = RETRYABLE_STATUSES.include?(status) || status >= 500

    # Exponential backoff with full jitter; retry-after wins when the server sends it.
    def backoff(attempt, retry_after)
      return [retry_after, 60].min if retry_after

      rand * [0.5 * (2**attempt), MAX_BACKOFF].min
    end

    def build_error(status, res)
      body = begin
        parse(res.body)
      rescue JSON::ParserError
        res.body
      end
      e = body.is_a?(Hash) && body["error"].is_a?(Hash) ? body["error"] : {}
      opts = { status: status, code: e["code"], request_id: e["request_id"] || res["x-request-id"], body: body }
      msg = e["message"] || "HTTP #{status}"
      case status
      when 400, 422 then ValidationError.new(msg, **opts)
      when 401 then AuthenticationError.new(msg, **opts)
      when 403 then PermissionError.new(msg, **opts)
      when 404 then NotFoundError.new(msg, **opts)
      when 429
        ra = res["retry-after"]
        RateLimitError.new(msg, retry_after: ra && Float(ra, exception: false), **opts)
      else APIError.new(msg, **opts)
      end
    end
  end
end
