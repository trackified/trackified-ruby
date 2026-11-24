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
end
