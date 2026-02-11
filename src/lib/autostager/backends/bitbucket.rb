require 'json'
require 'rest-client'

module Autostager
  module Backends
    # Bitbucket Server backend using REST API
    module Bitbucket
      module_function

      def username
        ENV['username']
      end

      def access_token
        ENV['access_token']
      end

      def git_server
        ENV['git_server'] || 'bitbucket.example.com'
      end

      def repo_slug
        ENV['repo_slug']
      end

      def project
        repo_slug.split('/')[0]
      end

      def repo
        repo_slug.split('/')[1]
      end

      def init
        # Bitbucket doesn't need initialization like Octokit
        username
      end

      def default_branch
        response = RestClient::Request.new(
          method: :get,
          url: "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/branches/default",
          user: username,
          password: access_token,
          verify_ssl: false
        ).execute
        results = JSON.parse(response.to_str)
        results['displayId']
      end

      def fetch_pull_requests
        response = RestClient::Request.new(
          method: :get,
          url: "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests",
          user: username,
          password: access_token,
          verify_ssl: false
        ).execute
        prs = JSON.parse(response.to_str)
        prs['values']
      end

      def add_comment(pr, comment)
        RestClient::Request.new(
          method: :post,
          url: "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr_id(pr)}/comments",
          user: username,
          password: access_token,
          verify_ssl: false,
          payload: { 'text' => comment }.to_json,
          headers: { accept: :json, content_type: :json }
        ).execute
      end

      def close_pr(pr)
        # First get current PR version (required by Bitbucket API)
        response = RestClient::Request.new(
          method: :get,
          url: "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr_id(pr)}",
          user: username,
          password: access_token,
          verify_ssl: false
        ).execute
        results = JSON.parse(response.to_str)
        pr_version = results['version']

        # Decline the PR
        RestClient::Request.new(
          method: :post,
          url: "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr_id(pr)}/decline?version=#{pr_version}",
          user: username,
          password: access_token,
          verify_ssl: false,
          headers: { content_type: :json }
        ).execute
      end

      def create_issue(_title, _body)
        # Bitbucket Server doesn't have the same issue creation concept
        # This is a no-op for Bitbucket
      end

      def repo_url
        "https://#{git_server}/scm/#{repo_slug}"
      end

      def from_clone_url(pr)
        clone_links = pr['fromRef']['repository']['links']['clone']
        (clone_links.select { |key| key.to_s.match(/http/) })[0]['href']
      end

      def to_clone_url(pr)
        clone_links = pr['toRef']['repository']['links']['clone']
        (clone_links.select { |key| key.to_s.match(/http/) })[0]['href']
      end

      def authenticated_url(url)
        url.dup.sub(%r{^(https://)(.*)}, '\1' + username + ':' + access_token + '@\2')
      end

      # PR accessor helpers - normalize PR data access
      def pr_id(pr)
        pr['id']
      end

      def pr_branch(pr)
        pr['fromRef']['displayId']
      end

      def pr_sha(pr)
        pr['fromRef']['latestCommit']
      end

      def pr_author_label(pr)
        "#{pr['author']['user']['slug']}:#{pr['fromRef']['displayId']}"
      end

      def pr_base_branch(pr)
        pr['toRef']['displayId']
      end

      def error_class
        StandardError
      end

      def error_message
        'Did you export "username", "access_token", and "repo_slug"?'
      end

      def clear_puppet_cache(environment)
        RestClient::Request.new(
          method: :delete,
          url: "https://puppet:8140/puppet-admin-api/v1/environment-cache?environment=#{environment}",
          verify_ssl: false,
          headers: { content_type: :json }
        ).execute
      end

      def supports_puppet_cache_clear?
        true
      end
    end
  end
end
