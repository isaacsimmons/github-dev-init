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
  GH_AUTH_STATUS="$?"
  set -e
  if [[ "${GH_AUTH_STATUS}" -ne "0" ]]; then
    AUTH_TOKEN_NAME="$( github-env-name "${host}" AUTH_TOKEN )"
    require-env "${AUTH_TOKEN_NAME}"
    echo "${!AUTH_TOKEN_NAME}" | gh auth login --hostname "${host}" --with-token
    echo "GH CLI successfully authenticated with ${host}"
  fi

  # Push your SSH key if not already present
  set +e
  GH_HOST="${host}" gh ssh-key list | grep -q "${SSH_PUBKEY}"
  SSH_KEY_PRESENT="$?"
  set -e
  if [[ "${SSH_KEY_PRESENT}" -ne "0" ]]; then
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

  for extra_arg in "${@:2}"; do
    if [[ "${extra_arg}" == "local-dir="* ]]; then
      local_dir="${extra_arg:10}"
    elif [[ "${extra_arg}" == "host="* ]]; then
      gh_host="${extra_arg:5}"
    elif [[ "${extra_arg}" == "fork" ]]; then
      fork="1"
    else
      exiterr "Unknown parameter for clone-repo: ${extra_arg}"
    fi
  done

  if [[ "${fork}" == "1" ]]; then
    upstream_org="${origin_org}"
    local gh_username_env_var="$( github-env-name "${gh_host}" USERNAME )"
    origin_org="${!gh_username_env_var}"
  fi

  local origin_url="git@${gh_host}:${origin_org}/${repo_name}.git"
  local upstream_url="git@${gh_host}:${upstream_org}/${repo_name}.git"

  cd "${REPO_ROOT_DIR}"
  if [[ -d "${local_dir}" ]]; then
    # Ensure that git remotes are set properly
    pushd "${local_dir}" > /dev/null
    local origin_remote="$(git remote get-url origin)"
    [[ "${origin_remote}" = "${origin_url}" ]] || exiterr "Origin not confgiured correctly in ${local_dir}"

    if [[ -n "${upstream_org:-}" ]]; then
      local upstream_remote="$(git remote get-url upstream)"
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

  cd "${local_dir}"
  if [[ -f ".dev-init-symlinks.txt" ]]; then
    makesymlinks
  fi
}

makesymlinks() {
  grep "^[^#]" ".dev-init-symlinks.txt" | while read -r line; do
    makesymlink $line
  done
}

# Needs to be called from within the repository directory
# Link points to the target
makesymlink() {
  local symlink_arg="${1}"

  local symlink_base_path="${PWD}/"
  local symlink_rel_path="${symlink_arg}"
  local default_target_prefix="$( basename "${PWD}" )/"
  if [[ "${symlink_arg}" = "~/"* ]]; then
    symlink_rel_path="${symlink_arg:2}"
    symlink_base_path="${HOME}/"
    default_target_prefix="home/"
  elif [[ "${symlink_arg}" = /* ]]; then
    symlink_base_path="/"
    symlink_rel_path="${symlink_arg:1}"
    default_target_prefix=""
  fi
  local symlink_abs_path="${symlink_base_path}${symlink_rel_path}"

  local target_rel_path=""
  local template_abs_path=""
  local create_empty="0"
  local is_optional="0"

  for extra_arg in "${@:2}"; do
    if [[ "${extra_arg}" == "template="* ]]; then
      template_abs_path="${PWD}/${extra_arg:9}"
    elif [[ "${extra_arg}" == "target="* ]]; then
      target_rel_path="${extra_arg:7}"
    elif [[ "${extra_arg}" == "empty" ]]; then
      create_empty="1"
    elif [[ "${extra_arg}" == "optional" ]]; then
      is_optional="1"
    else
      exiterr "Unknown parameter for makesymlink: ${extra_arg}"
    fi
  done

  # If no target parameter was specified, automatically generate one
  if [[ -z "${target_rel_path}" ]]; then
    target_rel_path="$( echo "${default_target_prefix}${symlink_rel_path}" | tr / _ )"
  fi
  local target_abs_path="${CONFIG_DIR}/${target_rel_path}"

  # First check if there's already a symlink there
  if [[ -L "${symlink_abs_path}" ]]; then
    if [[ "$(readlink -- "${symlink_abs_path}")" = "${target_abs_path}" ]]; then
      # Already exists and is correct
      return 0
    fi

    echo
    exiterr "Link at ${symlink_abs_path} exists but doesn't link to expected location"
  fi

  # Check if there's a file present where the symlink should be
  if [[ -f "${symlink_abs_path}" || -d "${symlink_abs_path}" ]]; then
    if [[ -f "${target_abs_path}" || -d "${target_abs_path}" ]]; then
      exiterr "Regular file already exists at link target ${target_abs_path}"
    fi

    # Special case when switching from local overrides files to symlinked ones
    # We'll switch the two files around here
    mv "${symlink_abs_path}" "${target_abs_path}"
    ln -s "${target_abs_path}" "${symlink_abs_path}"
    echo "Linked ${symlink_abs_path} to ${target_abs_path} (moved source file)"
    return 0
  fi

  # Simplest case, target exists just make the link
  if [[ -f "${target_abs_path}" || -d "${target_abs_path}" ]]; then
    ln -s "${target_abs_path}" "${symlink_abs_path}"
    echo "Linked ${symlink_abs_path} to ${target_abs_path}"
    return 0
  fi

  # Check the "create empty" flag and do so if set
  if [[ "${create_empty}" = "1" ]]; then
    touch "${target_abs_path}"
    ln -s "${target_abs_path}" "${symlink_abs_path}"
    echo "Linked ${symlink_abs_path} to ${target_abs_path} (created empty default)"
    return 0
  fi

  # If there's no template defined, then error out
  if [[ -z "${template_abs_path}" ]]; then
    if [[ "${is_optional}" = "1" ]]; then
      return 0
    fi
    exiterr "Source file not found ${symlink_abs_path}"
  fi

  # If the template points at a file that doesn't exist, then error out
  if [[ ! -f "${template_abs_path}" ]]; then
    exiterr "Template file ${template_abs_path} not found"
  fi

  # Copy the template file
  cp "${template_abs_path}" "${target_abs_path}"
  ln -s "${target_abs_path}" "${symlink_abs_path}"
  echo "Linked ${symlink_abs_path} to ${target_abs_path} (used template file)"
}

###### DONE FUNCTION DEFINITIONS #########

[[ "${EUID}" -eq 0 ]] && exiterr "Don't run this as root"

# Ensure dependencies are installed
if [[ "${OSTYPE}" == "darwin"* ]]; then
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
  if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    sudo apt install git
  elif [[ "${OSTYPE}" == "darwin"* ]]; then
    brew install git
  else
    exiterr "Unsupported OSTYPE ${OSTYPE}"
  fi
fi

if command -v gh &> /dev/null; then
  echo "GH CLI installed"
else
  echo "Intstalling GH CLI tools..."
  if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt update
    sudo apt install gh
  elif [[ "${OSTYPE}" == "darwin"* ]]; then
    brew install gh
  else
    exiterr "Unsupported OSTYPE ${OSTYPE}"
  fi
fi

# Setup config dir and copy config template if missing
[[ -d "${CONFIG_DIR}" ]] || mkdir -p "${CONFIG_DIR}"
[[ -f "${CONFIG_FILE}" ]] || cp "${SCRIPT_DIR}/github.env.template" "${CONFIG_FILE}"

# Load in environment vars from config
source "${CONFIG_FILE}"

# If there's a .dev-init-symlinks.txt file in your config dir already, ensure that all of those links have been created
# Note: this is early in the process, so if there are ssh keys or git config in there, it'll be linked first
if [[ -f "${CONFIG_DIR}/.dev-init-symlinks.txt" ]]; then
  # TODO: make sure this works with both absolute paths and with folders
  cd "${CONFIG_DIR}"
  makesymlinks
fi

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
GITHUB_HOSTS="${GITHUB_HOSTS:-GITHUB}"
for GITHUB_HOST in ${GITHUB_HOSTS//,/$IFS}; do
  ensure-github-auth "${GITHUB_HOST}"
done

[[ -f "${CONFIG_DIR}/repo-list.txt" ]] || cp "${SCRIPT_DIR}/repo-list.txt.template" "${CONFIG_DIR}/repo-list.txt"

# Clone all repos
grep "^[^#]" "${CONFIG_DIR}/repo-list.txt" | while read -r line; do
  clone-repo $line
done