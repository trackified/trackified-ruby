# frozen_string_literal: true

require "json"
require "openssl"

module Trackified
  # Verifies the x-tracking-signature header: "t=<unix seconds>,v1=<hex hmac-sha256>[,v1=<hex>...]".
  # During a secret rotation the header carries one v1 per secret; any match is valid.
  module WebhookSignature
    DEFAULT_TOLERANCE = 300
    HEADER = "x-tracking-signature"
    REASONS = %w[missing malformed timestamp mismatch].freeze

    # Result of verify_detailed. reason is nil when valid.
    VerificationResult = Struct.new(:valid, :reason, keyword_init: true) do
      def valid? = valid
    end

    module_function

    # @param raw_body [String] the request body exactly as received
    # @param header [String, nil] the x-tracking-signature value
    # @param secret [String, Array<String>] the webhook secret (whsec_...), or several during a rotation
    # @param tolerance [Integer] max clock skew in seconds
    # @return [Boolean]
    def verify(raw_body, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      verify_detailed(raw_body, header, secret, tolerance: tolerance, now: now).valid
    end

    # Like verify, but says why it failed.
    # @return [VerificationResult] valid, and reason: "missing" | "malformed" | "timestamp" | "mismatch" | nil
    def verify_detailed(raw_body, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      secrets = Array(secret).map(&:to_s).reject(&:empty?)
      return failure("missing") if header.to_s.strip.empty? || secrets.empty?

      t = nil
      sigs = []
      header.to_s.split(",").each do |kv|
        k, v = kv.strip.split("=", 2)
        t = v if k == "t"
        sigs << v.to_s if k == "v1"
      end
      return failure("malformed") unless t&.match?(/\A\d+\z/) && !sigs.empty? &&
                                         sigs.all? { |s| s.match?(/\A\h{64}\z/) }
      return failure("timestamp") if (now - t.to_i).abs > tolerance

      payload = "#{t}.#{raw_body}"
      expected = secrets.map { |s| OpenSSL::HMAC.hexdigest("SHA256", s, payload) }
      # Compare every pair (no early exit) so timing does not reveal which one matched.
      ok = expected.product(sigs).map { |e, s| OpenSSL.fixed_length_secure_compare(e, s.downcase) }.any?
      ok ? VerificationResult.new(valid: true, reason: nil) : failure("mismatch")
    end

    # @return [Trackified::Event]
    # @raise [SignatureVerificationError] with #reason
    def construct_event(raw_body, header, secret, tolerance: DEFAULT_TOLERANCE, now: Time.now.to_i)
      result = verify_detailed(raw_body, header, secret, tolerance: tolerance, now: now)
      unless result.valid
        raise SignatureVerificationError.new("Webhook signature verification failed (#{result.reason})",
                                             reason: result.reason)
      end

      Event.new(JSON.parse(raw_body))
    rescue JSON::ParserError => e
      raise SignatureVerificationError.new("Invalid webhook body: #{e.message}", reason: "malformed")
    end

    def failure(reason) = VerificationResult.new(valid: false, reason: reason)
    private_class_method :failure
  end
end
