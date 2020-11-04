require 'English'
require 'fileutils'
require 'autostager/cli'
require 'autostager/git_timeout'
require 'autostager/logger'
require 'autostager/pull_request'
require 'autostager/timeout'
require 'autostager/version'
require 'json'
require 'rest-client'
require 'pp'

# Top-level module namespace.
# rubocop:disable Metrics/ModuleLength
module Autostager
  module_function

  extend Autostager::Logger

  def username
    ENV['username']
  end

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
    response = RestClient::Request.new(
      :method => :get,
      :url => "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/branches/default",
      :user => username,
      :password => access_token,
      :verify_ssl => false
    ).execute
    results = JSON.parse(response.to_str)
    results['displayId']
  end

  # rubocop:disable MethodLength,Metrics/AbcSize
  def stage_upstream
    log "===> begin #{default_branch}"
    p = Autostager::PullRequest.new(
      default_branch,
      authenticated_url("https://#{git_server}/scm/#{repo_slug}"),
      base_dir,
      default_branch,
      authenticated_url("https://#{git_server}/scm/#{repo_slug}"),
    )
    p.clone unless p.staged?
    p.fetch
    return if p.rebase
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
 def process_pull(pr)
   log "#{pr['fromRef']['displayId']}"
   from_url = (pr['fromRef']['repository']['links']['clone'].select {|key| key.to_s.match(/http/) })[0]['href']
   to_url = (pr['toRef']['repository']['links']['clone'].select {|key| key.to_s.match(/http/) })[0]['href']

   log "from #{from_url}"
   log "to #{to_url}"

   p = Autostager::PullRequest.new(
     pr['fromRef']['displayId'],
      authenticated_url(from_url),
      base_dir,
      clone_dir(pr),
      authenticated_url(to_url),
   )

   if p.staged?
        log "===> staged"
        p.fetch
      if pr['fromRef']['latestCommit'] != p.local_sha
        log "===> reset hard"
        p.reset_hard
        add_comment = true
      else
        log "nothing to do on #{pr['id']} #{staging_dir(pr)}"
        add_comment = false
      end
      comment_or_close(p, pr, add_comment)
    else
        log "===> clone"
      p.clone
      comment_or_close(p, pr)
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  # rubocop:disable MethodLength,Metrics/AbcSize
  def comment_or_close(p, pr, add_comment = true)
 
    if p.up2date?("upstream/#{pr['toRef']['displayId']}")
      if add_comment
        comment = format(
          ':bell: Staged `%s` at revision %s on %s',
          clone_dir(pr),
          p.local_sha,
          Socket.gethostname,
        )
        response = RestClient::Request.new(
          :method => :post,
          :url => "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr['id']}/comments",
          :user => username,
          :password => access_token,
          :verify_ssl => false,
          :payload => {"text" => comment}.to_json,
          :headers => { :accept => :json, content_type: :json }
        ).execute

        log comment
      end
    else
      comment = format(
        ':boom: Unstaged since %s is dangerously behind upstream.',
        clone_dir(pr),
      )
      FileUtils.rm_rf staging_dir(pr), secure: true


	response = RestClient::Request.new(
	   :method => :post,
	   :url => "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr['id']}/comments",
	   :user => username,
	   :password => access_token,
	   :verify_ssl => false,
	   :payload => {"text" => comment}.to_json,
	   :headers => { :accept => :json, content_type: :json }
	).execute


	response = RestClient::Request.new(
	   :method => :post,
	   :url => "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests/#{pr['id']}/decline?version=5",
	   :user => username,
	   :password => access_token,
	   :verify_ssl => false,
	   :headers => {content_type: :json }
	).execute

      log comment
    end
  end
  # rubocop:enable MethodLength,Metrics/AbcSize

  def authenticated_url(s)
    s.dup.sub!(%r{^(https://)(.*)}, '\1' + username + ':' + access_token + '@\2')
  end

  def base_dir
    ENV['base_dir'] || '/opt/puppet/environments'
  end

  def clone_dir(pr)
    alphafy ("#{pr['author']['user']['slug']}:#{pr['fromRef']['displayId']}")

    # github
    # alphafy(pr.head.label)
  end

  def staging_dir(pr)
    File.join base_dir, clone_dir(pr)
  end

  def repo_slug
    ENV['repo_slug']
  end

  def project
    repo_slug.split("/")[0]
  end

  def repo
    repo_slug.split("/")[1]
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
    user = username

    # Handle the default branch differently because
    # we only ever rebase, never force-push.
    stage_upstream
    # Get open PRs.
    response = RestClient::Request.new(
      :method => :get,
      :url => "https://#{git_server}/rest/api/1.0/projects/#{project}/repos/#{repo}/pull-requests",
      :user => username,
      :password => access_token,
      :verify_ssl => false
    ).execute
    prs = JSON.parse(response.to_str)
    new_clones = prs['values'].map { |pr| clone_dir(pr) }
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
      prs['values'].each { |pr| process_pull pr }
    end
  rescue => e
    warn e.message
    warn e.backtrace
    warn 'Did you export "username" "access_token" and "repo_slug"?'
    exit(1)
  end
  # rubocop:enable MethodLength,Metrics/AbcSize
end
# rubocop:enable Metrics/ModuleLength
