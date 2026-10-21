# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

require_relative "version"
require_relative "errors"

module Shotwolf
  # Client for the ShotWolf API. Pass an API key (+sw_live_...+) or set the
  # +SHOTWOLF_API_KEY+ environment variable.
  #
  #   sw = Shotwolf::Client.new
  #   shot = sw.capture(url: "https://example.com", device: "iphone_15_pro")
  #   puts shot["image_url"]
  class Client
    DEFAULT_BASE_URL = "https://shotwolf.com"
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(api_key = nil, base_url: DEFAULT_BASE_URL, timeout: 60, max_retries: 2,
                   retry_backoff: 0.5, transport: nil)
      @api_key = api_key || ENV.fetch("SHOTWOLF_API_KEY", nil)
      if @api_key.nil? || @api_key.empty?
        raise Error.new("Missing API key. Pass api_key or set SHOTWOLF_API_KEY.", type: "unauthorized")
      end

      @base_url = base_url.sub(%r{/+\z}, "")
      @timeout = timeout
      @max_retries = max_retries
      @retry_backoff = retry_backoff
      @transport = transport || method(:net_http_transport)
    end

    # Capture a URL or HTML synchronously. POST /api/v1/captures
    def capture(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/captures", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Queue a capture and return immediately. POST /api/v1/captures/async
    def capture_async(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/captures/async", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Render one URL across 2-6 devices. POST /api/v1/capture/batch
    def batch(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/capture/batch", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Render a URL inside a device/social mockup. POST /api/v1/mockups
    def mockup(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/mockups", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Generate an Open Graph card from a template. POST /api/v1/og
    def og(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/og", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Convert a URL or HTML string to PDF. POST /api/v1/pdf
    def pdf(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/pdf", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Pixel-diff two screenshots. POST /api/v1/diffs
    def diff(idempotency_key: nil, timeout: nil, **params)
      request("POST", "/api/v1/diffs", body: params, idempotency_key: idempotency_key, timeout: timeout)
    end

    # Retrieve a single screenshot by ID. GET /api/v1/screenshots/:id
    def get_screenshot(id, timeout: nil)
      request("GET", "/api/v1/screenshots/#{id.to_i}", timeout: timeout)
    end

    # Get balance, tier and webhook secret. GET /api/v1/account
    def account(timeout: nil)
      request("GET", "/api/v1/account", timeout: timeout)
    end

    # Poll +get_screenshot+ until the shot is +done+ or +failed+. Returns the
    # final screenshot Hash; raises Shotwolf::Error on render failure or
    # Shotwolf::TimeoutError if the deadline passes.
    def wait_for(id, interval: 2.0, timeout: 120.0)
      deadline = monotonic + timeout
      loop do
        shot = get_screenshot(id)
        return shot if shot["status"] == "done"
        if shot["status"] == "failed"
          raise Error.new("Screenshot #{id} failed to render", type: "render_failed", status: 422)
        end
        raise TimeoutError.new(timeout) if monotonic + interval > deadline

        sleep(interval)
      end
    end

    private

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def request(method, path, body: nil, idempotency_key: nil, timeout: nil)
      url = @base_url + path
      req_timeout = timeout || @timeout
      headers = {
        "Authorization" => "Bearer #{@api_key}",
        "Accept" => "application/json",
        "User-Agent" => "shotwolf-ruby/#{VERSION}"
      }
      payload = nil
      unless body.nil?
        headers["Content-Type"] = "application/json"
        payload = JSON.generate(body)
      end
      headers["Idempotency-Key"] = idempotency_key if idempotency_key

      last_error = nil
      (0..@max_retries).each do |attempt|
        begin
          status, resp_headers, resp_body = @transport.call(method, url, headers, payload, req_timeout)
        rescue StandardError => e
          last_error = timeout_error?(e) ? TimeoutError.new(req_timeout) : e
          if attempt < @max_retries
            sleep(backoff(attempt))
            next
          end
          raise last_error
        end

        if status >= 200 && status < 300
          return resp_body.nil? || resp_body.empty? ? {} : JSON.parse(resp_body)
        end

        if RETRYABLE_STATUSES.include?(status) && attempt < @max_retries
          sleep(parse_retry_after(resp_headers) || backoff(attempt))
          next
        end

        raise to_error(status, resp_headers, resp_body)
      end

      raise(last_error || Error.new("Request failed"))
    end

    def net_http_transport(method, url, headers, body, timeout)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout

      klass = method == "GET" ? Net::HTTP::Get : Net::HTTP::Post
      req = klass.new(uri.request_uri)
      headers.each { |k, v| req[k] = v }
      req.body = body if body

      resp = http.request(req)
      resp_headers = {}
      resp.each_header { |k, v| resp_headers[k.downcase] = v }
      [resp.code.to_i, resp_headers, resp.body]
    end

    def timeout_error?(err)
      err.is_a?(Timeout::Error) || err.is_a?(Net::OpenTimeout) || err.is_a?(Net::ReadTimeout)
    end

    def backoff(attempt)
      @retry_backoff * (2**attempt)
    end

    def parse_retry_after(headers)
      raw = headers["retry-after"]
      return nil unless raw

      Float(raw)
    rescue ArgumentError, TypeError
      nil
    end

    def to_error(status, headers, body)
      type = nil
      message = "HTTP #{status}"
      begin
        data = JSON.parse(body.to_s)
        if data.is_a?(Hash) && data["error"].is_a?(Hash)
          type = data["error"]["type"]
          message = data["error"]["message"] || message
        end
      rescue JSON::ParserError
        # non-JSON body; keep the HTTP status message
      end
      Error.new(
        message,
        type: type || "unknown",
        status: status,
        request_id: headers["x-request-id"],
        retry_after: parse_retry_after(headers)
      )
    end
  end
end
