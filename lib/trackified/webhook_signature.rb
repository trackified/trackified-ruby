# frozen_string_literal: true

require "json"
require "openssl"

module Trackified
  # Verifies the x-tracking-signature header: "t=<unix seconds>,v1=<hex hmac-sha256>".
  module WebhookSignature
    DEFAULT_TOLERANCE = 300
    HEADER = "x-tracking-signature"

    module_function

    # @param raw_body [String] the request body exactly as received
    # @param header [String, nil] the x-tracking-signature value
    # @param secret [String] the webhook secret (whsec_...)
    # @param tolerance [Integer] max clock skew in seconds
    # @return [Boolean]
    def verify(raw_body, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      parts = header.to_s.split(",").to_h { |kv| kv.strip.split("=", 2) }
      t = parts["t"]
      sig = parts["v1"]
      return false unless t&.match?(/\A\d+\z/) && sig&.match?(/\A[0-9a-f]{64}\z/i)
      return false if (now - t.to_i).abs > tolerance

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{t}.#{raw_body}")
      OpenSSL.fixed_length_secure_compare(expected, sig.downcase)
    rescue ArgumentError
      false
    end

    # @return [Trackified::Event]
    # @raise [SignatureVerificationError]
    def construct_event(raw_body, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      unless verify(raw_body, header, secret, tolerance: tolerance, now: now)
        raise SignatureVerificationError, "Webhook signature verification failed"
      end

      Event.new(JSON.parse(raw_body))
    rescue JSON::ParserError => e
      raise SignatureVerificationError, "Invalid webhook body: #{e.message}"
    end
  end
end
