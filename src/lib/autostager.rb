require 'English'
require 'fileutils'
require 'autostager/cli'
require 'autostager/git_timeout'
require 'autostager/logger'
require 'autostager/pull_request'
require 'autostager/timeout'
require 'autostager/version'
require 'autostager/backends/github'
require 'autostager/backends/bitbucket'
require 'pp'

# Top-level module namespace.
# rubocop:disable Metrics/ModuleLength
module Autostager
  module_function

  extend Autostager::Logger

  # Select backend based on git_backend environment variable
  # Defaults to 'github' for backward compatibility
  def git_backend
    ENV['git_backend'] || 'github'
  end

  def backend
    @backend ||= case git_backend.downcase
                 when 'github'
                   Autostager::Backends::GitHub
                 when 'bitbucket'
                   Autostager::Backends::Bitbucket
                 else
                   raise "Unknown git_backend: #{git_backend}. Valid options: github, bitbucket"
                 end
  end

  # Convert a string into purely alphanumeric characters
  def alphafy(a_string)
    a_string.gsub(/[^a-z0-9_]/i, '_')
  end

  # Get the name of the default branch for the repo.
  # This is usually master in git, but
  # could also be "production" for a puppet repo.
  def default_branch
    backend.default_branch
  end

  # rubocop:disable MethodLength,Metrics/AbcSize
  def stage_upstream
    log "===> begin #{default_branch}"
    p = Autostager::PullRequest.new(
      default_branch,
      backend.authenticated_url(backend.repo_url),
      base_dir,
      default_branch,
      backend.authenticated_url(backend.repo_url),
    )
    p.clone unless p.staged?
    p.fetch

    # Clear puppet cache if backend supports it and branch is behind
    if backend.supports_puppet_cache_clear? && p.behind('upstream/master') > 0
      backend.clear_puppet_cache('master')
      log '===> puppet cache clear on master'
    end

    return if p.rebase

    # fast-forward failed, so raise awareness (GitHub only)
    backend.create_issue(
      "Failed to fast-forward #{default_branch} branch",
      ':bangbang: This probably means somebody force-pushed to the branch.',
    )
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
  def process_pull(pr)
    log "===> #{backend.pr_id(pr)} #{clone_dir(pr)}"

    from_url = backend.from_clone_url(pr)
    to_url = backend.to_clone_url(pr)

    log "from #{from_url}"
    log "to #{to_url}"

    p = Autostager::PullRequest.new(
      backend.pr_branch(pr),
      backend.authenticated_url(from_url),
      base_dir,
      clone_dir(pr),
      backend.authenticated_url(to_url),
    )

    if p.staged?
      log '===> staged'
      p.fetch
      if backend.pr_sha(pr) != p.local_sha
        log '===> reset hard'
        p.reset_hard
        add_comment = true
      else
        log "nothing to do on #{backend.pr_id(pr)} #{staging_dir(pr)}"
        add_comment = false
      end
      comment_or_close(p, pr, add_comment)
    else
      log '===> clone'
      p.clone
      comment_or_close(p, pr)
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
  def comment_or_close(p, pr, add_comment = true)
    if p.up2date?("upstream/#{backend.pr_base_branch(pr)}")
      if add_comment
        comment = format(
          ':bell: Staged `%s` at revision %s on %s',
          clone_dir(pr),
          p.local_sha,
          Socket.gethostname,
        )

        backend.add_comment(pr, comment)
        log comment

        # Clear puppet cache if backend supports it
        if backend.supports_puppet_cache_clear?
          backend.clear_puppet_cache(clone_dir(pr))
          log "===> puppet cache clear on #{clone_dir(pr)}"
        end
      end
    else
      comment = format(
        ':boom: Unstaged since %s is dangerously behind upstream.',
        clone_dir(pr),
      )
      FileUtils.rm_rf staging_dir(pr), secure: true

      backend.add_comment(pr, comment)
      backend.close_pr(pr)
      log comment
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  def base_dir
    ENV['base_dir'] || '/opt/puppet/environments'
  end

  def clone_dir(pr)
    alphafy(backend.pr_author_label(pr))
  end

  def staging_dir(pr)
    File.join base_dir, clone_dir(pr)
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
      'master',
      'main',
      'production',
    ]
  end

  # rubocop:disable MethodLength,Metrics/AbcSize
  def run
    log "===> Using #{git_backend} backend"
    backend.init

    # Handle the default branch differently because
    # we only ever rebase, never force-push.
    stage_upstream

    # Get open PRs.
    prs = backend.fetch_pull_requests

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
  rescue backend.error_class => e
    warn e.message
    warn e.backtrace if e.respond_to?(:backtrace)
    warn backend.error_message
    exit(1)
  end
  # rubocop:enable MethodLength,Metrics/AbcSize
end
# rubocop:enable Metrics/ModuleLength
