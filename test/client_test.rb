# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "shotwolf"

module TestHelper
  # Build a fake transport returning queued responses, recording calls.
  # Each response: { status:, body:, headers:, raise: }
  def fake_transport(responses)
    calls = []
    i = { n: 0 }
    transport = lambda do |method, url, headers, body, timeout|
      calls << { method: method, url: url, headers: headers.dup, body: body, timeout: timeout }
      spec = responses[[i[:n], responses.length - 1].min]
      i[:n] += 1
      raise spec[:raise] if spec[:raise]

      payload = spec[:body]
      raw = payload.nil? ? "" : JSON.generate(payload)
      [spec[:status], spec[:headers] || {}, raw]
    end
    [transport, calls]
  end

  def client(responses, **opts)
    transport, calls = fake_transport(responses)
    opts[:retry_backoff] = 0 unless opts.key?(:retry_backoff)
    sw = Shotwolf::Client.new("sw_live_test", transport: transport, **opts)
    [sw, calls]
  end
end

class ClientTest < Minitest::Test
  include TestHelper

  def test_missing_api_key_raises
    ENV.delete("SHOTWOLF_API_KEY")
    assert_raises(Shotwolf::Error) do
      Shotwolf::Client.new(transport: ->(*) { [200, {}, "{}"] })
    end
  end

  def test_reads_env_key
    ENV["SHOTWOLF_API_KEY"] = "sw_live_env"
    transport, calls = fake_transport([{ status: 200, body: { "balance_cr" => 5 } }])
    Shotwolf::Client.new(transport: transport).account
    assert_equal "Bearer sw_live_env", calls[0][:headers]["Authorization"]
  ensure
    ENV.delete("SHOTWOLF_API_KEY")
  end

  def test_module_new_delegates
    transport, = fake_transport([{ status: 200, body: {} }])
    sw = Shotwolf.new("sw_live_x", transport: transport)
    assert_instance_of Shotwolf::Client, sw
  end

  def test_capture_posts_json_and_returns_body
    sw, calls = client([{ status: 201, body: { "id" => 42, "status" => "done", "image_url" => "https://cdn/x.png" } }])
    res = sw.capture(url: "https://example.com", full_page: true)

    assert_equal "POST", calls[0][:method]
    assert_equal "https://shotwolf.com/api/v1/captures", calls[0][:url]
    assert_equal "Bearer sw_live_test", calls[0][:headers]["Authorization"]
    assert_equal "application/json", calls[0][:headers]["Content-Type"]
    assert_equal({ "url" => "https://example.com", "full_page" => true }, JSON.parse(calls[0][:body]))
    assert_equal({ "id" => 42, "status" => "done", "image_url" => "https://cdn/x.png" }, res)
  end

  def test_custom_base_url
    sw, calls = client([{ status: 201, body: { "id" => 1 } }], base_url: "http://localhost:6300/")
    sw.capture(url: "https://e.com")
    assert_equal "http://localhost:6300/api/v1/captures", calls[0][:url]
  end

  def test_idempotency_key_header
    sw, calls = client([{ status: 201, body: { "id" => 1 } }])
    sw.capture(url: "https://e.com", idempotency_key: "abc-123")
    assert_equal "abc-123", calls[0][:headers]["Idempotency-Key"]
  end

  def test_error_envelope_raises
    sw, = client([{ status: 402, body: { "error" => { "type" => "insufficient_credits", "message" => "Broke" } } }])
    err = assert_raises(Shotwolf::Error) { sw.capture(url: "https://e.com") }
    assert_equal "insufficient_credits", err.type
    assert_equal 402, err.status
    assert_equal "Broke", err.message
  end

  def test_error_carries_request_id
    sw, = client([{ status: 400, body: { "error" => { "type" => "invalid_params", "message" => "bad" } },
                    headers: { "x-request-id" => "req_9" } }])
    err = assert_raises(Shotwolf::Error) { sw.capture(url: "x") }
    assert_equal "req_9", err.request_id
  end

  def test_retries_on_429_then_succeeds
    sw, calls = client([
                         { status: 429, body: { "error" => { "type" => "rate_limited", "message" => "slow" } } },
                         { status: 201, body: { "id" => 7, "status" => "done" } }
                       ])
    res = sw.capture(url: "https://e.com")
    assert_equal 2, calls.length
    assert_equal 7, res["id"]
  end

  def test_gives_up_after_max_retries
    sw, calls = client([{ status: 503, body: { "error" => { "type" => "render_failed", "message" => "down" } } }],
                       max_retries: 1)
    err = assert_raises(Shotwolf::Error) { sw.capture(url: "https://e.com") }
    assert_equal 503, err.status
    assert_equal 2, calls.length
  end

  def test_no_retry_on_400
    sw, calls = client([{ status: 400, body: { "error" => { "type" => "invalid_params", "message" => "no" } } }])
    assert_raises(Shotwolf::Error) { sw.capture(url: "x") }
    assert_equal 1, calls.length
  end

  def test_retries_on_transport_error
    sw, calls = client([
                         { status: 0, raise: IOError.new("boom") },
                         { status: 201, body: { "id" => 3 } }
                       ])
    res = sw.capture(url: "https://e.com")
    assert_equal 3, res["id"]
    assert_equal 2, calls.length
  end

  def test_get_screenshot_is_get_no_body
    sw, calls = client([{ status: 200, body: { "id" => 5, "status" => "queued" } }])
    sw.get_screenshot(5)
    assert_equal "https://shotwolf.com/api/v1/screenshots/5", calls[0][:url]
    assert_equal "GET", calls[0][:method]
    assert_nil calls[0][:body]
  end

  def test_wait_for_polls_until_done
    sw, calls = client([
                         { status: 200, body: { "id" => 5, "status" => "processing" } },
                         { status: 200, body: { "id" => 5, "status" => "processing" } },
                         { status: 200, body: { "id" => 5, "status" => "done", "image_url" => "https://cdn/y.png" } }
                       ])
    res = sw.wait_for(5, interval: 0.001, timeout: 5)
    assert_equal "done", res["status"]
    assert_equal 3, calls.length
  end

  def test_wait_for_raises_on_failed
    sw, = client([{ status: 200, body: { "id" => 5, "status" => "failed" } }])
    err = assert_raises(Shotwolf::Error) { sw.wait_for(5, interval: 0.001, timeout: 5) }
    assert_equal "render_failed", err.type
  end

  def test_wait_for_times_out
    sw, = client([{ status: 200, body: { "id" => 5, "status" => "processing" } }])
    assert_raises(Shotwolf::TimeoutError) { sw.wait_for(5, interval: 0.01, timeout: 0.001) }
  end

  def test_endpoint_paths
    {
      mockup: [{ url: "https://e.com", frame: "iphone_15_pro" }, "https://shotwolf.com/api/v1/mockups"],
      og: [{ template: "blog_card" }, "https://shotwolf.com/api/v1/og"],
      pdf: [{ url: "https://e.com" }, "https://shotwolf.com/api/v1/pdf"],
      diff: [{ before_url: "https://a.com", after_url: "https://b.com" }, "https://shotwolf.com/api/v1/diffs"],
      batch: [{ url: "https://e.com", devices: %w[default iphone_15_pro] }, "https://shotwolf.com/api/v1/capture/batch"],
      capture_async: [{ url: "https://e.com" }, "https://shotwolf.com/api/v1/captures/async"]
    }.each do |meth, (kwargs, path)|
      sw, calls = client([{ status: 201, body: { "id" => 1 } }])
      sw.public_send(meth, **kwargs)
      assert_equal path, calls[0][:url], "#{meth} path"
    end
  end

  def test_account_get
    sw, calls = client([{ status: 200, body: { "email_address" => "a@b.co", "balance_cr" => 5 } }])
    acc = sw.account
    assert_equal "https://shotwolf.com/api/v1/account", calls[0][:url]
    assert_equal 5, acc["balance_cr"]
  end
end
