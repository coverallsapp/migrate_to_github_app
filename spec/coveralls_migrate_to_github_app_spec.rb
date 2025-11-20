# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CoverallsMigrateToGithubApp do
  it "has a version number" do
    expect(CoverallsMigrateToGithubApp::VERSION).not_to be nil
  end
end

RSpec.describe CoverallsMigrateToGithubApp::CLI do
  JSON_TYPE = {"Content-Type" => "application/json"}

  let(:coveralls_token) { "coveralls_pat_123" }
  let(:github_token) { "github_pat_abc123" }
  let(:org_name) { "coverallsapp" }

  let(:args) { ["start", "--coveralls-token=#{coveralls_token}",
                "--github-token=#{github_token}",
                "--org-name=#{org_name}" ]
            }

  let(:command) { CoverallsMigrateToGithubApp::CLI.start(args) }

  let(:urls) do
    {
        coveralls_repos: "https://coveralls.io/api/repos/github/#{org_name}",
        github_orgs: "https://api.github.com/user/orgs",
        github_installations: "https://api.github.com/user/installations",
        github_install: Addressable::Template.new("https://api.github.com/user/installations/{installation_id}/repositories/{repository_id}"),
        github_repo: Addressable::Template.new("https://api.github.com/repos/{owner}/{repo}")
   }
  end

  describe "#start" do
    before(:each) do
      # Stub Coveralls API - returns list of repos
      stub_request(:get, urls[:coveralls_repos])
        .to_return(status: 200, headers: JSON_TYPE, body: '[
          {"name":"coverallsapp/coveralls","github_install_id":null},
          {"name":"coverallsapp/gitsurance","github_install_id":null}
        ]')

      # Stub GitHub user/orgs validation
      stub_request(:get, urls[:github_orgs])
        .to_return(status: 200, headers: JSON_TYPE, body: '[{"login":"coverallsapp","id":123}]')

      # Stub GitHub installations API - find Coveralls Official app
      stub_request(:get, urls[:github_installations])
        .to_return(status: 200, headers: JSON_TYPE, body: '{
          "installations": [
            {
              "id": 35578911,
              "app_id": 54321,
              "app_slug": "coveralls-official",
              "account": {"login":"coverallsapp","id":123}
            }
          ]
        }')

      # Stub GitHub repo API - get repo IDs
      stub_request(:get, "https://api.github.com/repos/coverallsapp/coveralls")
        .to_return(status: 200, headers: JSON_TYPE, body: '{"id":7777,"name":"coveralls"}')
      stub_request(:get, "https://api.github.com/repos/coverallsapp/gitsurance")
        .to_return(status: 200, headers: JSON_TYPE, body: '{"id":8888,"name":"gitsurance"}')

      # Stub GitHub App installation API - add repos to app
      stub_request(:put, urls[:github_install])
        .to_return(status: 204, headers: JSON_TYPE, body: '')
    end

    context "valid arguments" do
      it { expect{command}.to_not raise_error }
      it { expect(command).to have_requested(:put, "https://api.github.com/user/installations/35578911/repositories/7777").once }
      it { expect(command).to have_requested(:put, "https://api.github.com/user/installations/35578911/repositories/8888").once }
      it { expect{command}.to output(a_string_including("Migration complete!")).to_stdout }
      it { expect{command}.to output(a_string_including("Found 2 repositories to migrate")).to_stdout }
    end

    context "invalid Coveralls token" do
      before(:each) do
        stub_request(:get, urls[:coveralls_repos]).to_return(status: 401, headers: JSON_TYPE, body: '{"error":"Unauthorized"}')
      end

      it { expect{command}.to raise_error(SystemExit) }
      it { expect{begin; command; rescue SystemExit; end}.to output(a_string_including("Error validating Coveralls token: 401")).to_stderr }
    end

    context "invalid GitHub token" do
      before(:each) do
        stub_request(:get, urls[:github_orgs]).to_return(status: 401, headers: JSON_TYPE, body: '{"message": "Requires authentication"}')
      end

      it { expect{command}.to raise_error(SystemExit) }
      it { expect{begin; command; rescue SystemExit; end}.to output(a_string_including("Error authenticating to GitHub: 401")).to_stderr }
    end

    context "Coveralls Official GitHub App not installed" do
      before(:each) do
        stub_request(:get, urls[:github_installations])
          .to_return(status: 200, headers: JSON_TYPE, body: '{"installations":[]}')
      end

      it { expect{command}.to raise_error(SystemExit) }
      it { expect{begin; command; rescue SystemExit; end}.to output(a_string_including("Coveralls Official GitHub App not found")).to_stderr }
    end

    context "error retrieving repositories from Coveralls" do
      before(:each) do
        stub_request(:get, urls[:coveralls_repos]).to_return(status: 500, headers: JSON_TYPE, body: '{"error":"Internal server error"}')
      end

      it { expect{command}.to raise_error(SystemExit) }
      it { expect{begin; command; rescue SystemExit; end}.to output(a_string_including("Error retrieving repositories from Coveralls: 500")).to_stderr }
    end

    context "error performing migration on a repo" do
      before(:each) do
        stub_request(:put, "https://api.github.com/user/installations/35578911/repositories/8888").to_return(status: 500, headers: JSON_TYPE, body: nil)
      end

      it { expect{command}.to_not raise_error }
      it { expect{command}.to output(a_string_including("Warning: Some repositories failed to migrate")).to_stdout }
      it { expect{command}.to output(a_string_including("Failed repositories:")).to_stdout }
      it { expect{command}.to output(a_string_including("coverallsapp/gitsurance")).to_stdout }
      it { expect{command}.to output(a_string_including("Migration complete!")).to_stdout }
    end

    context "not found error/not authorized during installation" do
      before(:each) do
        stub_request(:put, "https://api.github.com/user/installations/35578911/repositories/8888").to_return(status: 404, headers: JSON_TYPE, body: nil)
      end

      it { expect{command}.to_not raise_error }
      it { expect{command}.to output(a_string_including("Warning: Some repositories failed to migrate")).to_stdout }
      it { expect{command}.to output(a_string_including("Failed repositories:")).to_stdout }
      it { expect{command}.to output(a_string_including("coverallsapp/gitsurance")).to_stdout }
      it { expect{command}.to output(a_string_including("Migration complete!")).to_stdout }
    end

    context "no repos to migrate" do
      before(:each) do
        stub_request(:get, urls[:coveralls_repos])
          .to_return(status: 200, headers: JSON_TYPE, body: '[
            {"name":"coverallsapp/coveralls","github_install_id":16}
          ]')
      end

      it { expect{command}.to_not raise_error }
      it { expect{command}.to output(a_string_including("No migration required")).to_stdout }
    end
  end
end
