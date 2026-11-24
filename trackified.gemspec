# frozen_string_literal: true

require_relative "lib/trackified/version"

Gem::Specification.new do |s|
  s.name = "trackified"
  s.version = Trackified::VERSION
  s.authors = ["Trackified"]
  s.email = ["support@trackified.net"]
  s.summary = "Official Ruby client for the Trackified parcel-tracking API"
  s.description = "Track parcels across carriers, read event history and verify signed webhooks " \
                  "with the Trackified API. No runtime dependencies."
  s.homepage = "https://github.com/trackified/trackified-ruby"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.1"
  s.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "CHANGELOG.md", "LICENSE"]
  s.require_paths = ["lib"]
  s.metadata = {
    "homepage_uri" => "https://trackified.net",
    "documentation_uri" => "https://forumulate.com/p/trackified/docs",
    "source_code_uri" => "https://github.com/trackified/trackified-ruby",
    "changelog_uri" => "https://github.com/trackified/trackified-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/trackified/trackified-ruby/issues",
    "rubygems_mfa_required" => "true"
  }
end
