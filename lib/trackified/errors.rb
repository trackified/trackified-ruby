# frozen_string_literal: true

module Trackified
  # Base class for every error the SDK raises.
  class TrackifiedError < StandardError
    # @return [Integer, nil] HTTP status
    attr_reader :status
    # @return [String, nil] API error code, e.g. "not_found"
    attr_reader :code
    # @return [String, nil] request id to quote to support
    attr_reader :request_id
    # @return [Hash, String, nil] parsed response body
    attr_reader :body

    def initialize(message = nil, status: nil, code: nil, request_id: nil, body: nil)
      super(message)
      @status = status
      @code = code
      @request_id = request_id
      @body = body
    end
  end

  # 401
  class AuthenticationError < TrackifiedError; end
  # 403
  class PermissionError < TrackifiedError; end
  # 404
  class NotFoundError < TrackifiedError; end
  # 400 / 422
  class ValidationError < TrackifiedError; end

  # 429
  class RateLimitError < TrackifiedError
    # @return [Float, nil] seconds to wait, from the retry-after header
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **kwargs)
      super(message, **kwargs)
      @retry_after = retry_after
    end
  end

  # 5xx and any other unexpected status
  class APIError < TrackifiedError; end
  # Network failure or timeout; status is nil.
  class ConnectionError < TrackifiedError; end
  # Webhook signature did not verify.
  class SignatureVerificationError < TrackifiedError; end
end
