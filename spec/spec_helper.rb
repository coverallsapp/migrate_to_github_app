# frozen_string_literal: true

require "bundler/setup"
require "coveralls_migrate_to_github_app"
require "webmock/rspec"
require "pry"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    allow($stdout).to receive(:puts)
    allow($stderr).to receive(:puts)
  end

  WebMock.disable_net_connect!
end
