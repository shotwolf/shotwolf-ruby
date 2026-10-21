# ShotWolf Ruby SDK

Official Ruby client for the [ShotWolf](https://shotwolf.com) API - capture screenshots, render device mockups, generate Open Graph cards, convert HTML to PDF, and run pixel-level visual regression diffs through a single JSON HTTP API.

- Zero dependencies (standard library only, Ruby 3.0+)
- Built-in retries with backoff, idempotency keys, and an async polling helper

## Install

```bash
gem install shotwolf
```

Or in a Gemfile:

```ruby
gem "shotwolf"
```

## Quick start

Get an API key at [shotwolf.com/dashboard/api_keys](https://shotwolf.com/dashboard/api_keys).

```ruby
require "shotwolf"

sw = Shotwolf::Client.new  # reads SHOTWOLF_API_KEY, or pass Shotwolf::Client.new("sw_live_...")

shot = sw.capture(url: "https://example.com", full_page: true, dismiss_cookies: true)
puts shot["image_url"]
```

## Usage

### Screenshots

```ruby
# Sync - returns the image URL inline (~1-4s)
shot = sw.capture(url: "https://stripe.com", device: "iphone_15_pro")

# Async - queue and poll (or pass webhook_url for a callback)
queued = sw.capture_async(url: "https://stripe.com")
done = sw.wait_for(queued["id"])  # polls until status is done

# Batch - one page, many viewports (cheaper than N calls)
batch = sw.batch(url: "https://stripe.com", devices: ["default", "iphone_15_pro", "ipad_pro_12_9"])
```

### Device & social mockups

```ruby
mockup = sw.mockup(url: "https://stripe.com", frame: "macbook_air", bg: "gradient")
```

### Open Graph cards

```ruby
og = sw.og(template: "blog_card", variables: { title: "Ship faster", author: "Jane Doe" })
```

### HTML / URL to PDF

```ruby
pdf = sw.pdf(html: "<h1>Invoice #42</h1>", page_format: "A4", print_background: true)
```

### Visual regression diff

```ruby
diff = sw.diff(
  before_url: "https://staging.example.com",
  after_url: "https://example.com",
  ignore_regions: [{ x: 0, y: 0, width: 1280, height: 80 }]  # mask a dynamic header
)
puts "#{(diff['diff_ratio'] * 100).round(2)}% changed" unless diff["passed"]
```

### Account balance

```ruby
account = sw.account
puts account["balance_cr"], account["tier"]["name"]
```

## Idempotency

Pass `idempotency_key:` to make money-charging POSTs safe to retry. A repeat with
the same key and body within 24h replays the original response instead of
charging again.

```ruby
require "securerandom"
sw.capture(url: "https://example.com", idempotency_key: SecureRandom.uuid)
```

## Error handling

Any non-2xx response raises `Shotwolf::Error` carrying the API error `type`, HTTP
`status`, and `message`.

```ruby
begin
  sw.capture(url: "https://example.com")
rescue Shotwolf::Error => e
  # e.type == "insufficient_credits" -> top up at https://shotwolf.com/pricing
  warn [e.status, e.type, e.message, e.request_id].inspect
end
```

## Configuration

```ruby
sw = Shotwolf::Client.new(
  "sw_live_xxx",
  base_url: "https://shotwolf.com",  # override for self-host / testing
  timeout: 60,                       # per-request timeout in seconds
  max_retries: 2,                    # retries on 429 / 5xx
  retry_backoff: 0.5                 # base backoff, doubled per attempt
)
```

Retries honor the `Retry-After` header on `429` responses. `4xx` responses
other than `429` are never retried.

## API coverage

| Method | Endpoint |
| --- | --- |
| `capture(**params)` | `POST /api/v1/captures` |
| `capture_async(**params)` | `POST /api/v1/captures/async` |
| `batch(**params)` | `POST /api/v1/capture/batch` |
| `mockup(**params)` | `POST /api/v1/mockups` |
| `og(**params)` | `POST /api/v1/og` |
| `pdf(**params)` | `POST /api/v1/pdf` |
| `diff(**params)` | `POST /api/v1/diffs` |
| `get_screenshot(id)` | `GET /api/v1/screenshots/:id` |
| `wait_for(id)` | polls `get_screenshot` until `done`/`failed` |
| `account` | `GET /api/v1/account` |

Full parameter reference: [shotwolf.com/docs](https://shotwolf.com/docs).

## License

MIT
