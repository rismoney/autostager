require 'octokit'

module Autostager
  module Backends
    # GitHub backend using Octokit gem
    module GitHub
      module_function

      def client
        @client ||= Octokit::Client.new(access_token: access_token)
      end

      def access_token
        ENV['access_token']
      end

      def git_server
        ENV['git_server'] || 'github.com'
      end

      def repo_slug
        ENV['repo_slug']
      end

      def init
        Octokit.auto_paginate = true
        client.user.login
      end

      def default_branch
        client.repo(repo_slug).default_branch
      end

      def fetch_pull_requests
        client.pulls(repo_slug)
      end

      def add_comment(pr, comment)
        client.add_comment(repo_slug, pr_id(pr), comment)
      end

      def close_pr(pr)
        client.close_issue(repo_slug, pr_id(pr))
      end

      def create_issue(title, body)
        client.create_issue(repo_slug, title, body)
      end

      def repo_url
        "https://#{git_server}/#{repo_slug}"
      end

      def from_clone_url(pr)
        pr.head.repo.clone_url
      end

      def to_clone_url(pr)
        pr.base.repo.clone_url
      end

      def authenticated_url(url)
        url.dup.sub(%r{^(https://)(.*)}, '\1' + access_token + '@\2')
      end

      # PR accessor helpers - normalize PR data access
      def pr_id(pr)
        pr.number
      end

      def pr_branch(pr)
        pr.head.ref
      end

      def pr_sha(pr)
        pr.head.sha
      end

      def pr_author_label(pr)
        pr.head.label
      end

      def pr_base_branch(pr)
        pr.base.repo.default_branch
      end

      def error_class
        Octokit::Unauthorized
      end

      def error_message
        'Did you export "access_token" and "repo_slug"?'
      end

      # GitHub doesn't need puppet cache clearing by default
      def clear_puppet_cache(_environment)
        # No-op for GitHub backend
      end

      def supports_puppet_cache_clear?
        false
      end
    end
  end
end
