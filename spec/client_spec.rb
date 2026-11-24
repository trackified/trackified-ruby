# frozen_string_literal: true

RSpec.describe Trackified::Client do
  let(:base) { "https://api.test" }
  let(:client) { described_class.new(api_key: "tk_test_abc", base_url: base, max_retries: 2) }
  let(:json) { { "Content-Type" => "application/json" } }
  let(:tracking) { { "id" => "trk_1", "tracking_number" => "9434", "status" => "in_transit", "events" => [] } }

  before { allow(client).to receive(:sleep) }

  def err(code, msg = "nope") = { error: { code: code, message: msg, request_id: "req_1" } }.to_json

  it "reads api key and base url from env" do
    stub_const("ENV", ENV.to_h.merge("TRACKIFIED_API_KEY" => "tk_env", "TRACKIFIED_BASE_URL" => "https://env.test/"))
    expect(described_class.new.base_url).to eq("https://env.test")
  end

  it "raises without an api key" do
    stub_const("ENV", ENV.to_h.except("TRACKIFIED_API_KEY"))
    expect { described_class.new }.to raise_error(Trackified::AuthenticationError)
  end

  it "creates a tracking with auth, user agent and an idempotency key" do
    stub = stub_request(:post, "#{base}/v1/trackings")
           .with(body: { tracking_number: "9434", carrier: "usps" }.to_json,
                 headers: { "Authorization" => "Bearer tk_test_abc", "User-Agent" => "trackified-ruby/#{Trackified::VERSION}",
                            "Idempotency-Key" => /\A\h{8}-\h{4}-4\h{3}-\h{4}-\h{12}\z/ })
           .to_return(status: 201, body: tracking.to_json, headers: json)
    t = client.trackings.create(tracking_number: "9434", carrier: "usps")
    expect(t).to be_a(Trackified::Tracking)
    expect(t.status).to eq(Trackified::TrackingStatus::IN_TRANSIT)
    expect(stub).to have_been_requested
  end

  it "reuses the idempotency key across retries" do
    keys = []
    stub_request(:post, "#{base}/v1/trackings")
      .with { |r| keys << r.headers["Idempotency-Key"] }
      .to_return({ status: 503, body: err("unavailable") }, { status: 201, body: tracking.to_json })
    client.trackings.create(tracking_number: "9434", idempotency_key: "order-1")
    expect(keys).to eq(%w[order-1 order-1])
  end

  it "retries 429 honouring retry-after, then succeeds" do
    stub_request(:get, "#{base}/v1/trackings/trk_1")
      .to_return({ status: 429, body: err("rate_limited"), headers: { "retry-after" => "3" } },
                 { status: 200, body: tracking.to_json })
    expect(client.trackings.get("trk_1").id).to eq("trk_1")
    expect(client).to have_received(:sleep).with(3.0)
  end

  it "retries network errors and raises ConnectionError when exhausted" do
    stub = stub_request(:get, "#{base}/v1/account/usage").to_timeout
    expect { client.usage.get }.to raise_error(Trackified::ConnectionError)
    expect(stub).to have_been_requested.times(3)
  end

  it "raises APIError after exhausting 5xx retries" do
    stub = stub_request(:get, "#{base}/v1/account/usage").to_return(status: 500, body: err("internal"))
    expect { client.usage.get }.to raise_error(Trackified::APIError) { |e| expect(e.status).to eq(500) }
    expect(stub).to have_been_requested.times(3)
  end

  {
    400 => Trackified::ValidationError, 422 => Trackified::ValidationError, 401 => Trackified::AuthenticationError,
    403 => Trackified::PermissionError, 404 => Trackified::NotFoundError, 409 => Trackified::APIError
  }.each do |status, klass|
    it "maps #{status} to #{klass} without retrying" do
      stub = stub_request(:get, "#{base}/v1/trackings/x").to_return(status: status, body: err("c#{status}", "m"))
      expect { client.trackings.get("x") }.to raise_error(klass) { |e|
        expect([e.status, e.code, e.message, e.request_id]).to eq([status, "c#{status}", "m", "req_1"])
      }
      expect(stub).to have_been_requested.once
    end
  end

  it "exposes retry_after on RateLimitError" do
    c = described_class.new(api_key: "k", base_url: base, max_retries: 0)
    stub_request(:get, "#{base}/v1/account/usage").to_return(status: 429, body: err("rl"),
                                                             headers: { "retry-after" => "7" })
    expect { c.usage.get }.to raise_error(Trackified::RateLimitError) { |e| expect(e.retry_after).to eq(7.0) }
  end

  it "auto-paginates trackings" do
    stub_request(:get, "#{base}/v1/trackings?limit=2&status=delivered").to_return(
      body: { data: [tracking, tracking.merge("id" => "trk_2")], pagination: { limit: 2, offset: 0, total: 3 } }.to_json
    )
    stub_request(:get, "#{base}/v1/trackings?limit=2&offset=2&status=delivered").to_return(
      body: { data: [tracking.merge("id" => "trk_3")], pagination: { limit: 2, offset: 2, total: 3 } }.to_json
    )
    page = client.trackings.list(limit: 2, status: "delivered")
    expect(page.data.map(&:id)).to eq(%w[trk_1 trk_2])
    expect(page.map(&:id)).to eq(%w[trk_1 trk_2 trk_3])
  end

  it "covers the remaining operations" do
    ok = ->(b) { { status: 200, body: b.to_json } }
    list = { data: [{ id: "x", displayName: "USPS" }], pagination: { limit: 50, offset: 0, total: 1 } }
    stub_request(:post, "#{base}/v1/trackings/bulk").to_return(status: 207, body: { data: [{ ok: true, tracking: tracking }, { ok: false, error: "bad" }] }.to_json)
    stub_request(:put, "#{base}/v1/trackings/trk_1").with(body: { custom_id: "o1" }.to_json).to_return(ok.call(tracking))
    stub_request(:delete, "#{base}/v1/trackings/trk_1").to_return(ok.call(deleted: true, id: "trk_1"))
    stub_request(:post, "#{base}/v1/trackings/trk_1/retrack").to_return(status: 202, body: { queued: true, tracking: tracking }.to_json)
    stub_request(:get, "#{base}/v1/carriers").to_return(ok.call(list))
    stub_request(:get, "#{base}/v1/carriers/usps").to_return(ok.call(id: "usps", displayName: "USPS"))
    stub_request(:get, "#{base}/v1/carriers/detect?number=9434").to_return(ok.call(candidates: [{ carrier: "usps", confidence: 0.9 }]))
    stub_request(:get, "#{base}/v1/carriers/catalog?q=ups").to_return(ok.call(total: 0, data: []))
    stub_request(:get, "#{base}/v1/carriers/status").to_return(ok.call(counts: {}))
    stub_request(:post, "#{base}/v1/webhooks").to_return(status: 201, body: { id: "wh_1", secret: "whsec_x" }.to_json)
    stub_request(:get, "#{base}/v1/webhooks").to_return(ok.call(list))
    stub_request(:delete, "#{base}/v1/webhooks/wh_1").to_return(status: 200, body: "")
    stub_request(:post, "#{base}/v1/webhooks/wh_1/test").to_return(ok.call(signature: "t=1,v1=a", body: {}))
    stub_request(:get, "#{base}/v1/webhook-deliveries").to_return(ok.call(list))
    stub_request(:post, "#{base}/v1/account/api-keys").to_return(status: 201, body: { id: "key_1", token: "tk_test_new" }.to_json)
    stub_request(:get, "#{base}/v1/account/api-keys").to_return(ok.call(list))
    stub_request(:delete, "#{base}/v1/account/api-keys/key_1").to_return(status: 200, body: "")

    expect(client.trackings.bulk_create([{ tracking_number: "1" }, { tracking_number: "" }]).first["tracking"]).to be_a(Trackified::Tracking)
    expect(client.trackings.update("trk_1", custom_id: "o1").id).to eq("trk_1")
    expect(client.trackings.delete("trk_1")).to eq("deleted" => true, "id" => "trk_1")
    expect(client.trackings.retrack("trk_1")["tracking"].id).to eq("trk_1")
    expect(client.carriers.list.first.display_name).to eq("USPS")
    expect(client.carriers.get("usps").display_name).to eq("USPS")
    expect(client.carriers.detect("9434").first.carrier).to eq("usps")
    expect(client.carriers.catalog(q: "ups")["total"]).to eq(0)
    expect(client.carriers.status).to eq("counts" => {})
    expect(client.webhooks.create(url: "https://x.test").secret).to eq("whsec_x")
    expect(client.webhooks.list.data.first).to be_a(Trackified::Webhook)
    expect(client.webhooks.delete("wh_1")).to be_nil
    expect(client.webhooks.test("wh_1")["signature"]).to eq("t=1,v1=a")
    expect(client.webhook_deliveries.list.data.first).to be_a(Trackified::WebhookDelivery)
    expect(client.api_keys.create(name: "ci", mode: "test").token).to eq("tk_test_new")
    expect(client.api_keys.list.data.first).to be_a(Trackified::ApiKey)
    expect(client.api_keys.revoke("key_1")).to be_nil
  end
end
