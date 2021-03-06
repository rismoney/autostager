require 'English'
require 'fileutils'
require 'autostager/cli'
require 'autostager/git_timeout'
require 'autostager/logger'
require 'autostager/pull_request'
require 'autostager/timeout'
require 'autostager/version'
require 'octokit'
require 'pp'

# Top-level module namespace.
# rubocop:disable Metrics/ModuleLength
module Autostager
  module_function

  extend Autostager::Logger

  def access_token
    ENV['access_token']
  end

  def git_server
    ENV['git_server'] || 'github.com'
  end

  # Convert a string into purely alphanumeric characters
  def alphafy(a_string)
    a_string.gsub(/[^a-z0-9_]/i, '_')
  end

  # Get the name of the default branch for the repo.
  # This is usually master in git, but
  # could also be "production" for a puppet repo.
  def default_branch
    @client.repo(repo_slug).default_branch
  end

  # rubocop:disable MethodLength,Metrics/AbcSize
  def stage_upstream
    log "===> begin #{default_branch}"
    p = Autostager::PullRequest.new(
      default_branch,
      authenticated_url("https://#{git_server}/#{repo_slug}"),
      base_dir,
      default_branch,
      authenticated_url("https://#{git_server}/#{repo_slug}"),
    )
    p.clone unless p.staged?
    p.fetch
    return if p.rebase

    # fast-forward failed, so raise awareness.
    @client.create_issue(
      repo_slug,
      "Failed to fast-forward #{default_branch} branch",
      ':bangbang: This probably means somebody force-pushed to the branch.',
    )
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
  def process_pull(pr)
    log "===> #{pr.number} #{clone_dir(pr)}"
    p = Autostager::PullRequest.new(
      pr.head.ref,
      authenticated_url(pr.head.repo.clone_url),
      base_dir,
      clone_dir(pr),
      authenticated_url(pr.base.repo.clone_url),
    )
    if p.staged?
      p.fetch
      if pr.head.sha != p.local_sha
        p.reset_hard
        add_comment = true
      else
        log "nothing to do on #{pr.number} #{staging_dir(pr)}"
        add_comment = false
      end
      comment_or_close(p, pr, add_comment)
    else
      p.clone
      comment_or_close(p, pr)
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
  def comment_or_close(p, pr, add_comment = true)
    if p.up2date?("upstream/#{pr.base.repo.default_branch}")
      if add_comment
        comment = format(
          ':bell: Staged `%s` at revision %s on %s',
          clone_dir(pr),
          p.local_sha,
          Socket.gethostname,
        )
        client.add_comment repo_slug, pr.number, comment
        log comment
      end
    else
      comment = format(
        ':boom: Unstaged since %s is dangerously behind upstream.',
        clone_dir(pr),
      )
      FileUtils.rm_rf staging_dir(pr), secure: true
      client.add_comment repo_slug, pr.number, comment
      client.close_issue repo_slug, pr.number
      log comment
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  def authenticated_url(s)
    s.dup.sub!(%r{^(https://)(.*)}, '\1' + access_token + '@\2')
  end

  def base_dir
    ENV['base_dir'] || '/opt/puppet/environments'
  end

  def clone_dir(pr)
    alphafy(pr.head.label)
  end

  def staging_dir(pr)
    File.join base_dir, clone_dir(pr)
  end

  def repo_slug
    ENV['repo_slug']
  end

  def client
    @client ||= Octokit::Client.new(access_token: access_token)
  end

  def timeout_seconds
    result = 120
    if ENV.key?('timeout')
      result = ENV['timeout'].to_i
      raise 'timeout must be greater than zero seconds' if result <= 0
    end
    result
  end

  # A list of directories we never discard.
  def safe_dirs
    [
      '.',
      '..',
      'production',
    ]
  end

  # rubocop:disable MethodLength,Metrics/AbcSize
  def run
    Octokit.auto_paginate = true
    user = client.user
    user.login

    # Handle the default branch differently because
    # we only ever rebase, never force-push.
    stage_upstream

    # Get open PRs.
    prs = client.pulls(repo_slug)

    # Set of PR clone dirs.
    new_clones = prs.map { |pr| clone_dir(pr) }

    # Discard directories that do not have open PRs.
    if File.exist?(base_dir)
      discard_dirs = Dir.entries(base_dir) - safe_dirs - new_clones
      discard_dirs.map { |d| File.join(base_dir, d) }.each do |dir|
        log "===> Unstage #{dir} since PR is closed."
        FileUtils.rm_rf dir, secure: true
      end
    end

    # Process current PRs.
    Autostager::Timeout.timeout(timeout_seconds, GitTimeout) do
      prs.each { |pr| process_pull pr }
    end
  rescue Octokit::Unauthorized => e
    warn e.message
    warn 'Did you export "access_token" and "repo_slug"?'
    exit(1)
  end
  # rubocop:enable MethodLength,Metrics/AbcSize
end
# rubocop:enable Metrics/ModuleLength
