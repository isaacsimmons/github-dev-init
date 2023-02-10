# GitHub Dev Init

This script is designed to quickly setup a code directory with repositories hosted on GitHub.
It ensures that git and the GitHub CLI tools are configured and that basic authorization has been setup.
You can then declaratively list the repositories to clone and it will ensure that they exist and are configured as expected.
Finally, if the repositories themselves contain idempotent setup scripts, those can be automatically invoked as well.

# Dependencies

This should be usable with minimal dependencies

* macOS or apt-based linux (debian, ubuntu, etc)
* bash
* ssh-keygen
* curl
* tar

# Usage

## Step 1: Download

    mkdir -p ~/.local/share/dev-init && curl -SsL https://api.github.com/repos/isaacsimmons/github-dev-init/tarball/main | tar xz --strip-components=1 -C ~/.local/share/dev-init

Optional: symlink this somewhere on your path

    ln -s ~/.local/share/dev-init/install.sh ~/bin/dev-init

You can also clone the repo instead of using the one-liner install.

## Step 2: Run

    ~/.local/share/dev-init/install.sh

or, if you followed the optional symlink step you need only type

    dev-init

The install script is repeatable and idempotent.
It may prompt you to fill out additional information in your config directory (see below).

# Configuration

There are two main files that drive the configuration for the install script.

1. `~/.config/dev-init/github.env`: This contains your authentication credentials and basic configuration
1. `~/.config/dev-init/repo-list.txt`: This contains a list of repositories to clone (and optionally fork)

See `github.env.template` and `repo-list.txt.template` in this directory for additional details and examples.

Note: this follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html) for config files and the default config folder can be overridden with the `$XDG_CONFIG_HOME` environment variable.
