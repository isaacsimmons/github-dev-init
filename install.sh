#!/usr/bin/env bash

set -euo pipefail

#TODO: apply consistent style guide (Google Shell Styleguide, ShellCheck, etc)

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/dev-init"
CONFIG_FILE="${CONFIG_DIR}/github.env"
echo "Using config in ${CONFIG_DIR}/"

# Define some helper functions
exiterr() {
  >&2 echo "ERROR: ${1}"
  exit 1
}

require-env() {
  local var_name="${1}"
  [[ -z "${!var_name:-}" ]] && exiterr "${CONFIG_FILE} missing required environtment variable: ${var_name}"
  return 0
}

github-env-name() {
  local host="${1}"
  local suffix="${2}"
  echo "$( echo "${host}" | tr "[:lower:]" "[:upper:]" | tr . _ )_${suffix}"
}

ensure-github-auth() {
  local host="${1}"

  set +e
  gh auth status --hostname "${host}" &> /dev/null
  local gh_auth_status="$?"
  set -e
  if [[ "${gh_auth_status}" -ne "0" ]]; then
    local auth_token_name
    auth_token_name="$( github-env-name "${host}" AUTH_TOKEN )"
    require-env "${auth_token_name}"
    echo "${!auth_token_name}" | gh auth login --hostname "${host}" --with-token
    echo "GH CLI successfully authenticated with ${host}"
  fi

  # Push your SSH key if not already present
  set +e
  GH_HOST="${host}" gh ssh-key list | grep -q "${SSH_PUBKEY}"
  local ssh_key_present="$?"
  set -e
  if [[ "${ssh_key_present}" -ne "0" ]]; then
    echo "Uploading SSH public key to ${host}"
    GH_HOST="${host}" gh ssh-key add "${HOME}/.ssh/id_rsa.pub" -t "DevInit-$( uname -n )-$( date +"%Y" )"
  fi
}

clone-repo() {
  local arr_repo_arg=(${1//\// })
  local org_name="${arr_repo_arg[0]}"
  local repo_name="${arr_repo_arg[1]}"

  local gh_host="github.com"
  local local_dir="${repo_name}"
  local fork="0"
  local origin_org="${org_name}"
  local upstream_org=""
  # TODO: some way to specify a git branch other than the default?

  for extra_arg in "${@:2}"; do
    if [[ "${extra_arg}" == "local-dir="* ]]; then
      local_dir="${extra_arg:10}"
    elif [[ "${extra_arg}" == "host="* ]]; then
      gh_host="${extra_arg:5}"
    elif [[ "${extra_arg}" == "fork" ]]; then
      fork="1"
    fi
  done

  if [[ "${fork}" == "1" ]]; then
    upstream_org="${origin_org}"
    local gh_username_env_var
    gh_username_env_var="$( github-env-name "${gh_host}" USERNAME )"
    origin_org="${!gh_username_env_var}"
  fi

  local origin_url="git@${gh_host}:${origin_org}/${repo_name}.git"
  local upstream_url="git@${gh_host}:${upstream_org}/${repo_name}.git"

  cd "${REPO_ROOT_DIR}"
  if [[ -d "${local_dir}" ]]; then
    # Ensure that git remotes are set properly
    pushd "${local_dir}" > /dev/null
    local origin_remote
    origin_remote="$(git remote get-url origin)"
    [[ "${origin_remote}" = "${origin_url}" ]] || exiterr "Origin not confgiured correctly in ${local_dir}"

    if [[ -n "${upstream_org:-}" ]]; then
      local upstream_remote
      upstream_remote="$(git remote get-url upstream)"
      [[ "${upstream_remote}" = "${upstream_url}" ]] || exiterr "Upstream not confgiured correctly in ${local_dir}"
    fi

    popd > /dev/null
  elif [[ "${fork}" == "1" ]]; then
    echo "Cloning from ${origin_url} into ${local_dir}"
    GH_HOST="${gh_host}" gh repo fork "${upstream_url}" --clone -- "${local_dir}"
  else
    echo "Cloning from ${origin_url} into ${local_dir}"
    GH_HOST="${gh_host}" gh repo clone "${origin_url}" "${local_dir}"
  fi
}

run-repo-setup() {
  local arr_repo_arg=(${1//\// })
  local repo_name="${arr_repo_arg[1]}"

  local local_dir="${repo_name}"
  local install_script=""

  for extra_arg in "${@:2}"; do
    if [[ "${extra_arg}" == "local-dir="* ]]; then
      local_dir="${extra_arg:10}"
    elif [[ "${extra_arg}" == "install-script="* ]]; then
      install_script="${extra_arg:15}"
    fi
  done

  cd "${REPO_ROOT_DIR}/${local_dir}"
  if [[ -n "${install_script}" ]]; then
    "./${install_script}"
  fi
}

###### DONE FUNCTION DEFINITIONS #########

[[ "${EUID}" -eq 0 ]] && exiterr "Don't run this as root"

# Ensure dependencies are installed
if [[ "${OSTYPE}" == "darwin"* ]]; then
  if ! command -v brew &> /dev/null; then
    echo "Intstalling brew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

if ! command -v git &> /dev/null; then
  echo "Installing git..."
  if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    # TODO: non-apt
    sudo apt install git
  elif [[ "${OSTYPE}" == "darwin"* ]]; then
    brew install git
  else
    exiterr "Unsupported OSTYPE ${OSTYPE}"
  fi
fi

if ! command -v gh &> /dev/null; then
  echo "Intstalling GH CLI tools..."
  if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh
  elif [[ "${OSTYPE}" == "darwin"* ]]; then
    brew install gh
  else
    exiterr "Missing dependency. Install GH command line tools"
  fi
fi

# Setup config dir and copy config template if missing
[[ -d "${CONFIG_DIR}" ]] || mkdir -p "${CONFIG_DIR}"
[[ -f "${CONFIG_FILE}" ]] || cp "${SCRIPT_DIR}/github.env.template" "${CONFIG_FILE}"

# Load in environment vars from config
source "${CONFIG_FILE}"

# Setup repo root directory
REPO_ROOT_DIR="${REPO_ROOT_DIR:-${HOME}/code}"
[[ -d "${REPO_ROOT_DIR}" ]] || mkdir -p "${REPO_ROOT_DIR}"

# Make sure we have SSH keys setup as expected
# TODO: support for ed25519 keys?
if [[ ! -f "${HOME}/.ssh/id_rsa" ]]; then
  # create one if missing
  echo "Creating new ssh key"
  ssh-keygen -t rsa -b 4096
fi
SSH_PUBKEY="$( cut -d " " -f 2 "${HOME}/.ssh/id_rsa.pub" )"

# Setup 
require-env GIT_DISPLAY_NAME
require-env GIT_EMAIL
if [[ "$(git config --global --get user.name)" != "${GIT_DISPLAY_NAME}" ]]; then
  echo "Setting git config user.name"
  git config --global user.name "${GIT_DISPLAY_NAME}"
fi
if [[ "$(git config --global --get user.email)" != "${GIT_EMAIL}" ]]; then
  echo "Setting git config user.email"
  git config --global user.email "${GIT_EMAIL}"
fi

# Ensure GH CLI is setup to use SSH
if [[ "$(gh config get git_protocol)" != "ssh" ]]; then
  echo "Setting gh cli tools to use ssh"
  gh config set git_protocol ssh
fi

# Make sure the GH CLI is authenticated with all defined github hosts
GITHUB_HOSTS="${GITHUB_HOSTS:-github.com}"
for GITHUB_HOST in ${GITHUB_HOSTS//,/$IFS}; do
  ensure-github-auth "${GITHUB_HOST}"
done

[[ -f "${CONFIG_DIR}/repo-list.txt" ]] || cp "${SCRIPT_DIR}/repo-list.txt.template" "${CONFIG_DIR}/repo-list.txt"

# Clone all repos
grep "^[^#]" "${CONFIG_DIR}/repo-list.txt" | while read -r line; do
  clone-repo $line
done

# Setup all repos
grep "^[^#]" "${CONFIG_DIR}/repo-list.txt" | while read -r line; do
  run-repo-setup $line
done
