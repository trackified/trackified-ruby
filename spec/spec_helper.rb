# frozen_string_literal: true

require "trackified"
require "webmock/rspec"

WebMock.disable_net_connect!

RSpec.configure do |c|
  c.disable_monkey_patching!
  c.filter_run_excluding live: true unless ENV["TRACKIFIED_API_KEY"]
end
