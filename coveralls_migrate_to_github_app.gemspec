
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "coveralls_migrate_to_github_app/version"

Gem::Specification.new do |spec|
  spec.name          = "coveralls_migrate_to_github_app"
  spec.version       = CoverallsMigrateToGithubApp::VERSION
  spec.authors       = ["Coveralls"]
  spec.email         = ["support@coveralls.io"]

  spec.summary       = "Migrate Coveralls repositories from OAuth App to GitHub App access"
  spec.description   = "CLI tool to migrate Coveralls repositories from OAuth App to the Coveralls Official GitHub App, supporting orgs with 100+ repositories"
  spec.homepage      = "https://github.com/coverallsapp/migrate_to_github_app"
  spec.license       = "MIT"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|assets)/}) }
  end
  spec.bindir        = "bin"
  spec.executables   = "coveralls_migrate_to_github_app"
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.4.2"
  spec.add_development_dependency "pry-byebug", "~> 3.6.0"

  spec.add_dependency "thor", "~> 0.20.0"
  spec.add_dependency "http", "~> 3.3.0"
end
