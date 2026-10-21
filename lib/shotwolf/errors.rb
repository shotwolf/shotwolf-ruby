# frozen_string_literal: true

module Shotwolf
  # Raised for any non-2xx API response. +type+ mirrors the API error envelope
  # (invalid_params, insufficient_credits, rate_limited, ...). +status+ is the
  # HTTP status code (0 for client-side/transport errors).
  class Error < StandardError
    attr_reader :type, :status, :request_id, :retry_after

    def initialize(message, type: "unknown", status: 0, request_id: nil, retry_after: nil)
      super(message)
      @type = type
      @status = status
      @request_id = request_id
      @retry_after = retry_after
    end
  end

  # Raised when a request exceeds the configured timeout.
  class TimeoutError < Error
    def initialize(timeout)
      super("Request timed out after #{timeout}s", type: "timeout", status: 0)
    end
  end
end
