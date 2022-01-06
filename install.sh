#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# rename to dotfiles dir?
CONFIG_DIR="${CONFIG_DIR:-$HOME/.dotfiles}"
CONFIG_FILE="${CONFIG_DIR}/github.env"
echo "Using config in $CONFIG_DIR"

# Define some helper functions
exiterr() {
  >&2 echo "ERROR: ${1}"
  exit 1
}

require-env() {
  local var_name="${1}"
  [ -z "${!var_name:-}" ] && exiterr "${CONFIG_FILE} missing required environtment variable: ${var_name}"
  return 0
}

github-env-name() {
  local host="${1}"
  local suffix="${2}"
  echo "$( echo "$host" | tr [:lower:] [:upper:] | tr . _ )_$suffix"
}

check-github-auth() {
  local host="${1}"

#  echo $AUTH_TOKEN_NAME
#  require-env $AUTH_TOKEN_NAME
#  echo ${!AUTH_TOKEN_NAME}

  set +e
  gh auth status --hostname $host &> /dev/null
  GH_AUTH_STATUS="$?"
  set -e
  if [ "${GH_AUTH_STATUS}" -ne "0" ]; then
    AUTH_TOKEN_NAME="$( github-env-name $host AUTH_TOKEN )"
    require-env $AUTH_TOKEN_NAME
    echo "${!AUTH_TOKEN_NAME}" | gh auth login --hostname $host --with-token
  else
    echo "GH CLI authenticated"
  fi

  # Push your SSH key if not already present
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
[ -f "${CONFIG_FILE}" ] || cp "${SCRIPT_DIR}/github.env.template" "${CONFIG_FILE}"

# Load in environment vars, apply defaults as needed
source "${CONFIG_FILE}"

# If there's a .dotfiles-links file in your config dir already, ensure that all of those links have been created
# Note: this is pretty early in the process, so if you have your sshkeys or git config in there, it'll be linked
#       before we start checking them
if [ -f "${CONFIG_DIR}/.dotfile-links" ]; then
  "${SCRIPT_DIR}/make-symlinks.sh" "${CONFIG_DIR}/.dotfile-links"
fi

# Setup repo root directory
REPO_ROOT_DIR="${REPO_ROOT_DIR:-$HOME/code}"
[ -d "${REPO_ROOT_DIR}" ] || mkdir -p "${REPO_ROOT_DIR}"

# Make sure we have SSH keys setup as expected
# TODO: actually, I want them to be symlinks into my config directory???
if [ ! -f ${HOME}/.ssh/id_rsa ]; then
  # create one if missing
  exiterr "No SSH key found"
fi

# Setup 
require-env GIT_DISPLAY_NAME
require-env GIT_EMAIL
if [ "$(git config --global --get user.name)" != "${GIT_DISPLAY_NAME}" ]; then
  echo "Setting git config user.name"
  git config --global user.name "${GIT_DISPLAY_NAME}"
fi
if [ "$(git config --global --get user.email)" != "${GIT_EMAIL}" ]; then
  echo "Setting git config user.email"
  git config --global user.email "${GIT_EMAIL}"
fi

# Ensure GH CLI is setup to use SSH
if [ "$(gh config get git_protocol)" != "ssh" ]; then
  echo "Setting gh cli tools to use ssh"
  gh config set git_protocol ssh
fi

# Make sure the GH CLI is authenticated with all defined github hosts
GITHUB_HOSTS="${GITHUB_HOSTS:-GITHUB}"
for GITHUB_HOST in ${GITHUB_HOSTS//,/$IFS}; do
  check-github-auth $GITHUB_HOST
done


[ -f "${CONFIG_DIR}/repo-list.txt" ] || cp "${SCRIPT_DIR}/repo-list.txt.template" "${CONFIG_DIR}/repo-list.txt"

# Clone all repos (exiterr if none found)
