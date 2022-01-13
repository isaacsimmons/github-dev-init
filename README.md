# GitHub Dev Init

This script is designed to quickly setup a code directory with repositories hosted on GitHub.
It ensures that git and the GitHub CLI tools are configured and that basic authorization has been setup.
You can then declaratively list the repositories to clone and it will ensure that they exist and are configured as expected.
Those repositories can optionally specify a list of configuration files which should reside outside in an external config directory and be symlinked in.

# Dependencies

This should be usable with minimal dependencies

* macOS or apt-based linux (debian, ubuntu, etc)
* bash
* curl
* tar
* ssh-keygen

# Usage

## Step 1: Download

    mkdir -p ~/.local/share/dev-init && curl -SsL git.io/JSSVe | tar xz --strip-components=1 -C $_

Note: You can use whatever directory you like, you need not store it in `~/.local/share/dev-init`

## Step 2: Run

    ~/.local/share/dev-init/install.sh

The install script is repeatable and idempotent.
It may prompt you to fill out additional information in your config directory (see below).

# Configuration

There are three main files that drive the configuration for the install script.

1. `~/.config/dev-init/github.env`: This contains your authentication credentials and basic configuration
1. `~/.config/dev-init/repo-list.txt`: This contains a list of repositories to clone (and optionally fork)
1. `~/.config/dev-init/.dev-init-symlinks.txt` (optional): This contains directives for additional files (probably dotfiles from your home directory) to symlink into `~/.config/dev-init/`

See `github.env.template`, `repo-list.txt.template`, and `.dev-init-symlinks.txt.template` in this directory for additional details and examples.

Note: this follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) for config files and the default config folder can be overridden with the `$XDG_CONFIG_HOME` environment variable.
