# frozen_string_literal: true

RSpec.describe Trackified::WebhookSignature do
  let(:secret) { "whsec_trackified_test_vector" }
  let(:body) { '{"id":"evt_test","type":"tracking.updated","data":{"id":"trk_123"}}' }
  let(:t) { 1_792_560_000 }
  let(:sig) { "19752dd2fca1872cc8aa6cc36c412fce3bbfa120480580bdb1ad9d7957dfc9f4" }
  let(:header) { "t=#{t},v1=#{sig}" }

  it "accepts the shared test vector" do
    expect(described_class.verify(body, header, secret, now: t)).to be true
  end

  it "rejects a flipped hex digit" do
    flipped = sig.sub(/\A./) { |c| c == "1" ? "2" : "1" }
    expect(described_class.verify(body, "t=#{t},v1=#{flipped}", secret, now: t)).to be false
  end

  it "rejects a different body" do
    expect(described_class.verify("#{body} ", header, secret, now: t)).to be false
  end

  it "rejects a timestamp outside the tolerance" do
    expect(described_class.verify(body, header, secret, now: t + 301)).to be false
    expect(described_class.verify(body, header, secret, now: t - 301)).to be false
    expect(described_class.verify(body, header, secret, now: t + 301, tolerance: 600)).to be true
  end

  it "rejects malformed headers" do
    ["", nil, "garbage", "t=abc,v1=#{sig}", "v1=#{sig}", "t=#{t}", "t=#{t},v1=zz", "t=#{t},v1=#{sig[0..-3]}"].each do |h|
      expect(described_class.verify(body, h, secret, now: t)).to be(false), h.inspect
    end
  end

  it "constructs an event or raises" do
    event = described_class.construct_event(body, header, secret, now: t)
    expect(event.type).to eq("tracking.updated")
    expect(event.data).to eq("id" => "trk_123")
    expect { described_class.construct_event(body, header, "wrong", now: t) }
      .to raise_error(Trackified::SignatureVerificationError)
  end

  it "is reachable from client.webhooks" do
    client = Trackified::Client.new(api_key: "tk_test_x")
    expect(client.webhooks.verify(body, header, secret)).to be false # real clock is far from t
  end

  describe "dual-signature vector (secret rotation)" do
    let(:secret_b) { "whsec_trackified_test_vector_b" }
    let(:sig_b) { "aaa4b846892609125e20b07a531d46e9e4614d8eec8d6dd3ecccae877b58111f" }
    let(:dual) { "t=#{t},v1=#{sig_b},v1=#{sig}" }

    it "verifies with A alone, B alone and [A, B]" do
      expect(described_class.verify(body, dual, secret, now: t)).to be true
      expect(described_class.verify(body, dual, secret_b, now: t)).to be true
      expect(described_class.verify(body, dual, [secret, secret_b], now: t)).to be true
      expect(described_class.verify(body, dual, "whsec_other", now: t)).to be false
    end

    it "accepts a header where only the second v1 matches" do
      expect(described_class.verify(body, "t=#{t},v1=#{'0' * 64},v1=#{sig}", secret, now: t)).to be true
    end
  end

  it "reports the rejection reason" do
    {
      ["", secret] => "missing", [nil, secret] => "missing", [header, ""] => "missing", [header, []] => "missing",
      ["garbage", secret] => "malformed", ["t=abc,v1=#{sig}", secret] => "malformed",
      ["v1=#{sig}", secret] => "malformed", ["t=#{t}", secret] => "malformed", ["t=#{t},v1=zz", secret] => "malformed",
      [header, "wrong"] => "mismatch"
    }.each do |(h, s), reason|
      r = described_class.verify_detailed(body, h, s, now: t)
      expect([r.valid?, r.reason]).to eq([false, reason]), [h, s].inspect
    end
    expect(described_class.verify_detailed(body, header, secret, now: t + 301).reason).to eq("timestamp")
    ok = described_class.verify_detailed(body, header, secret, now: t)
    expect([ok.valid, ok.reason]).to eq([true, nil])
  end

  it "raises SignatureVerificationError with a reason" do
    expect { described_class.construct_event(body, header, secret, now: t + 999) }
      .to raise_error(Trackified::SignatureVerificationError) { |e| expect(e.reason).to eq("timestamp") }
  end

  it "types event data per type" do
    trk = { "id" => "trk_1", "status" => "delivered" }
    changed = Trackified::Event.new("type" => "tracking.status_changed",
                                    "data" => { "tracking" => trk, "previous_status" => "in_transit",
                                                "current_status" => "delivered" })
    plain = Trackified::Event.new("type" => "tracking.delivered", "data" => trk)
    [changed, plain].each do |e|
      expect(e.tracking).to eq(Trackified::Tracking.new(trk))
      expect(Trackified::Webhook.tracking_of(e).id).to eq("trk_1")
    end
    expect([changed.previous_status, changed.current_status]).to eq(%w[in_transit delivered])
    expect(plain.previous_status).to be_nil
    expect(Trackified::Client.new(api_key: "k").webhooks.tracking_of(changed).id).to eq("trk_1")
  end
end
