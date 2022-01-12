# GitHub Dev Init

Mission statement

# Dependencies

* macOS or apt-based linux (debian, ubuntu, etc)
* bash
* curl
* tar
* ssh-keygen

# Install

## Step 1: Download Scripts

    mkdir -p ~/.local/share/dev-init && curl -SsL git.io/JSSVe | tar xz --strip-components=1 -C $_

Note: You can pick a different directory than `~/.local/share/dev-init`

## Step 2: Install Deps

    ~/.local/share/dev-init/install.sh

This is repeatable
It may prompt you to fill out additional information in your config directory
Note: follows the XDG Base Directory Specification for config files and the default config folder can be overridden with the `$XDG_CONFIG_HOME` environment variable.

## Step 3: Configuration

Fill in env file
Provide a repository list

## Step 4: Now clone stuff

Nah, just use the same install.sh, detect if files are present. prompt for them if not, and use them if so
