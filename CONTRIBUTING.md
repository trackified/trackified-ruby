# Contributing

```sh
bundle install
bundle exec rake            # rubocop + rspec
bundle exec rbs -I sig validate
```

Unit tests must not hit the network (WebMock blocks it). `spec/live_spec.rb` runs only when
`TRACKIFIED_API_KEY` is set and creates then deletes one tracking. Keep runtime dependencies at zero.
Update `sig/trackified.rbs` and `CHANGELOG.md` with any public API change.
