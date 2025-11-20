# frozen_string_literal: true

require "thor"
require "http"

module CoverallsMigrateToGithubApp
  class CLI < Thor

    JSON_HEADER = "application/json"
    GITHUB_JSON_HEADER = "application/vnd.github.v3+json"
    GITHUB_INSTALLATIONS_PREVIEW_HEADER = "application/vnd.github.v3+json, application/vnd.github.machine-man-preview+json"

    COVERALLS_API_BASE = "https://coveralls.io/api"
    COVERALLS_REPOS_URL = "#{COVERALLS_API_BASE}/repos/github/{org_name}"
    GITHUB_ORGS_URL = "https://api.github.com/user/orgs"
    GITHUB_USER_INSTALLATIONS_URL = "https://api.github.com/user/installations"
    GITHUB_INSTALL_URL = "https://api.github.com/user/installations/{installation_id}/repositories/{repository_id}"
    GITHUB_REPO_URL = "https://api.github.com/repos/{owner}/{repo}"

    attr_accessor :coveralls_token, :github_token, :org_name, :repos_to_migrate, :github_installation_id, :errors

    def self.exit_on_failure?
      true
    end

    desc "start", "Migrate Coveralls repositories from OAuth App to GitHub App"
    long_desc <<-LONGDESC
      `coveralls_migrate_to_github_app start` will migrate your Coveralls repositories
      from OAuth App access to the Coveralls Official GitHub App.

      This tool is designed for organizations with 100+ repositories that cannot use
      the standard GitHub UI migration workflow.
    LONGDESC
    option :coveralls_token, banner: 'Coveralls Personal API Token', type: :string, required: :true
    option :github_token, banner: 'GitHub Personal Access Token', type: :string, required: :true
    option :org_name, banner: 'GitHub organization name', type: :string, required: :true
    def start
      setup
      @coveralls_token = options[:coveralls_token]
      @github_token = options[:github_token]
      @org_name = options[:org_name]

      validate_coveralls_token
      validate_github_credentials
      find_github_app_installation
      fetch_migration_info
      migrate
      report
    end

    no_commands do
      def setup
        @errors = Array.new
        @repos_to_migrate = Array.new
      end

      def validate_coveralls_token
        response = HTTP.headers(accept: JSON_HEADER, "Authorization" => "token #{@coveralls_token}")
                       .get(coveralls_repos_url(@org_name))
        unless response.code == 200
          raise Thor::Error.new "Error validating Coveralls token: #{response.code}: #{response.to_s}"
        end
      end

      def validate_github_credentials
        response = HTTP.headers(accept: GITHUB_JSON_HEADER)
                       .auth("token #{@github_token}")
                       .get(GITHUB_ORGS_URL)
        unless response.code == 200
          raise Thor::Error.new "Error authenticating to GitHub: #{response.code}: #{response.to_s}"
        end
      end

      def find_github_app_installation
        response = HTTP.headers(accept: GITHUB_INSTALLATIONS_PREVIEW_HEADER)
                       .auth("token #{@github_token}")
                       .get(GITHUB_USER_INSTALLATIONS_URL)
        unless response.code == 200
          raise Thor::Error.new "Error fetching GitHub App installations: #{response.code}: #{response.to_s}"
        end

        installations = response.parse["installations"]
        coveralls_installation = installations.find do |installation|
          installation["app_slug"] == "coveralls-official"
        end

        unless coveralls_installation
          raise Thor::Error.new "Coveralls Official GitHub App not found. Please install it first via https://coveralls.io"
        end

        # Verify the installation is for the specified org
        if coveralls_installation["account"]["login"] != @org_name
          raise Thor::Error.new "Coveralls Official app installation found, but not for organization '#{@org_name}'. Found: '#{coveralls_installation["account"]["login"]}'"
        end

        @github_installation_id = coveralls_installation["id"]
      end

      def coveralls_repos_url(org_name)
        COVERALLS_REPOS_URL.sub('{org_name}', org_name)
      end

      def fetch_migration_info
        response = HTTP.headers(accept: JSON_HEADER, "Authorization" => "token #{@coveralls_token}")
                       .get(coveralls_repos_url(@org_name))
        unless response.code == 200
          raise Thor::Error.new "Error retrieving repositories from Coveralls: #{response.code}: #{response.to_s}"
        end

        repos_data = response.parse

        # Filter repos that need migration (those without github_install_id or with github_app_disabled)
        # and build list with GitHub repo IDs
        repos_data.each do |repo|
          # Only migrate repos that aren't already using the GitHub App
          if repo["github_install_id"].nil? || repo["github_app_disabled"]
            @repos_to_migrate << {
              "name" => repo["name"],
              "github_id" => nil  # Will be fetched in migrate method
            }
          end
        end

        puts "Found #{@repos_to_migrate.length} repositories to migrate"
      end

      def migrate
        @repos_to_migrate.each do |repo|
          owner, repo_name = parse_repo_name(repo["name"])

          # Get GitHub repository ID
          github_repo_id = get_github_repo_id(owner, repo_name)
          unless github_repo_id
            @errors << "#{repo["name"]}: Could not fetch GitHub repository ID"
            next
          end

          # Add repository to GitHub App installation
          response = HTTP.headers(accept: GITHUB_INSTALLATIONS_PREVIEW_HEADER)
                         .auth("token #{@github_token}")
                         .put(github_install_url(@github_installation_id, github_repo_id))

          if response.code == 204
            puts "✓ Added #{repo["name"]} to Coveralls Official GitHub App"
            # TODO: Update Coveralls database here
            # update_coveralls_repo(repo["name"], @github_installation_id)
          else
            @errors << "#{repo["name"]}: Failed to add to GitHub App (#{response.code})"
          end
        end
      end

      def get_github_repo_id(owner, repo_name)
        response = HTTP.headers(accept: GITHUB_JSON_HEADER)
                       .auth("token #{@github_token}")
                       .get(github_repo_url(owner, repo_name))

        if response.code == 200
          response.parse["id"]
        else
          nil
        end
      end

      def github_install_url(installation_id, repo_id)
        GITHUB_INSTALL_URL.sub('{installation_id}', installation_id.to_s).sub('{repository_id}', repo_id.to_s)
      end

      def github_repo_url(owner, repo)
        GITHUB_REPO_URL.sub('{owner}', owner).sub('{repo}', repo)
      end

      def parse_repo_name(repo_name)
         repo_name.split('/')
      end


      def report
        puts "\n" + "="*60
        unless @errors.empty?
          puts "⚠ Warning: Some repositories failed to migrate"
          puts "\nPlease ensure your GitHub token has admin rights to the organization."
          puts "For help, contact support@coveralls.io\n"
          puts "Failed repositories:"
          @errors.each do |error|
            puts "  ✗ #{error}"
          end
          puts ""
        end

        if @repos_to_migrate.empty?
          puts "No migration required - all repositories are already using the GitHub App"
        else
          successful_count = @repos_to_migrate.length - @errors.length
          puts "Migration Summary:"
          puts "  Total repositories: #{@repos_to_migrate.length}"
          puts "  Successfully migrated: #{successful_count}"
          puts "  Failed: #{@errors.length}"
          puts "\n✓ Migration complete!"
        end
        puts "="*60
      end
    end
  end
end
