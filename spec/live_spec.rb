# frozen_string_literal: true

# Runs only when TRACKIFIED_API_KEY is set. Creates one tracking and deletes it.
RSpec.describe "live API", live: true do
  before { WebMock.allow_net_connect! }
  after { WebMock.disable_net_connect! }

  it "creates, reads, lists and deletes a tracking" do
    client = Trackified::Client.new(base_url: ENV["TRACKIFIED_BASE_URL"] || ENV.fetch("TRACKIFIED_API_BASE", nil))
    t = client.trackings.create(tracking_number: "9434650110837017316201", carrier: "usps")
    begin
      expect(client.trackings.get(t.id).tracking_number).to eq("9434650110837017316201")
      expect(client.trackings.list(limit: 1).data.size).to be <= 1
      expect(client.carriers.detect("9434650110837017316201").first.carrier).to eq("usps")
      expect(client.usage.get.plan).to be_a(String)
    ensure
      client.trackings.delete(t.id)
    end
  end
end
