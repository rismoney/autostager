Autostager
==========

Automatically stage a local directory based on pull requests from GitHub or Bitbucket Server.
<br />
For non-Ruby versions, see [Ports](#ports) below.

Build status for master branch: [![Circle CI](https://circleci.com/gh/jumanjihouse/autostager/tree/master.svg?style=svg&circle-token=a5b167be1f709009108ca0aaec1613fd9e843cc1)](https://circleci.com/gh/jumanjihouse/autostager/tree/master)


Installation
------------

Add this line to your application's Gemfile:

    gem 'puppet-autostager'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install puppet-autostager


Usage
-----

### Backend Selection

Autostager supports both GitHub and Bitbucket Server. Set the `git_backend` environment variable to select your backend:

```bash
# For GitHub (default)
export git_backend=github

# For Bitbucket Server
export git_backend=bitbucket
```

### GitHub Configuration

Create an access token as described at
https://github.com/octokit/octokit.rb#oauth-access-tokens
then export the following environment variables:

```bash
export git_backend=github
export repo_slug=owner/repo
export access_token=<your 40-char token>
export base_dir=/tmp/puppet/environments

# Optional: Set an alternate GitHub Enterprise server (default: github.com)
export git_server=git.example.com
export OCTOKIT_API_ENDPOINT=https://git.example.com/api/v3/
```

### Bitbucket Server Configuration

Create a personal access token in Bitbucket Server, then export the following environment variables:

```bash
export git_backend=bitbucket
export repo_slug=PROJECT/repo
export username=your_username
export access_token=<your personal access token>
export git_server=bitbucket.example.com
export base_dir=/tmp/puppet/environments
```

### Common Options

```bash
# Enable debug logging
export debug=anything

# Set a timeout for git operations (default 120 seconds)
export timeout=180

# Override the default 30 second interval
export sleep_interval=60

# Or run as a single-shot operation
export sleep_interval=0
```

### Running

```bash
autostager
```

### Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `git_backend` | No | `github` | Backend to use: `github` or `bitbucket` |
| `repo_slug` | Yes | - | Repository identifier (`owner/repo` for GitHub, `PROJECT/repo` for Bitbucket) |
| `access_token` | Yes | - | Personal access token for API authentication |
| `username` | Bitbucket only | - | Username for Bitbucket authentication |
| `git_server` | No | `github.com` | Git server hostname |
| `base_dir` | No | `/opt/puppet/environments` | Base directory for staged environments |
| `timeout` | No | `120` | Timeout in seconds for git operations |
| `sleep_interval` | No | `30` | Interval between runs (0 for single-shot) |
| `debug` | No | - | Enable debug logging if set |
| `OCTOKIT_API_ENDPOINT` | GitHub Enterprise only | - | API endpoint for GitHub Enterprise |


Build workflow
--------------

We use CircleCI to build and publish to rubygems.org:

![simplified workflow](assets/rubygems-workflow.png)

If build is clean on master branch, CircleCI pushes the
built gem to [https://rubygems.org/gems/puppet-autostager](https://rubygems.org/gems/puppet-autostager).


Ports
-----

* Python: https://github.com/Jfach/autostager
