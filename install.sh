#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CONFIG_DIR=~/.dotfiles

exiterr() {
  >&2 echo "ERROR: ${1}"
  exit 1
}

[ "${EUID}" -eq 0 ] && exiterr "Don't run this as root"

# Ensure dependencies are installed
if [[ "$OSTYPE" == "darwin"* ]]; then
  if command -v brew &> /dev/null; then
    echo "Brew installed"
  else
    echo "Intstalling brew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

if command -v git &> /dev/null; then
  echo "Git installed"
else
  echo "Installing git..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    sudo apt install git
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install git
  else
    exiterr "Unsupported OSTYPE $OSTYPE"
  fi
fi

if command -v gh &> /dev/null; then
  echo "GH CLI installed"
else
  echo "Intstalling GH CLI tools..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    brew install gh
  else
    exiterr "Unsupported OSTYPE $OSTYPE"
  fi
fi

# Setup config dir and copy config template if missing
[ -d "${CONFIG_DIR}" ] || mkdir -p "${CONFIG_DIR}"
[ -f "${CONFIG_DIR}/.env" ] || cp "${SCRIPT_DIR}/.env.template" "${CONFIG_DIR}/.env"

# Load in environment vars, apply defaults as needed
source "${CONFIG_DIR}/.env"
DEV_ROOT_DIRECTORY="${DEV_ROOT_DIRECTORY:-/Volumes/dev}"


# Setup dev root directory
[ -d "${DEV_ROOT_DIRECTORY}" ] || mkdir -p "${DEV_ROOT_DIRECTORY}"

# Make sure we have SSH keys setup as expected
# TODO: actually, I want them to be symlinks into my config directory???
if [ ! -f ~/.ssh/id_rsa ]; then
  # create one if missing
  exiterr "No SSH key found"  
fi

[ -z "${GIT_DISPLAY_NAME}" ] || echoerr "GIT_DISPLAY_NAME undefined"
[ -z "${GIT_EMAIL}" ] || echoerr "GIT_EMAIL undefined"
if [ "$(git config --global --get user.name)" != "${GIT_DISPLAY_NAME}" ]; then
  echo "Setting git config user.name"
  git config --global user.name "${GIT_DISPLAY_NAME}"
fi
if [ "$(git config --global --get user.email)" != "${GIT_EMAIL}" ]; then
  echo "Setting git config user.email"
  git config --global user.email "${GIT_EMAIL}"
fi

# Make sure the GH CLI is authenticated
set +e
gh auth status --hostname github.com &> /dev/null
GH_AUTH_STATUS="$?"
set -e
if [ "${GH_AUTH_STATUS}" -ne "0" ]; then
  [ -z "${GITHUB_AUTH_TOKEN}" ] || echoerr "GITHUB_AUTH_TOKEN undefined"
  echo "${GITHUB_AUTH_TOKEN}" | gh auth login --hostname github.com --with-token
else
  echo "GH CLI authenticated"
fi

# Ensure GH CLI is setup to use SSH
if [ "$(gh config get git_protocol)" != "ssh" ]; then
  echo "Setting gh cli tools to use ssh"
  gh config set git_protocol ssh
fi
