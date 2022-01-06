#!/usr/bin/env bash

set -euo pipefail

exiterr() {
  >&2 echo "ERROR: ${1}"
  exit 1
}

if [[ "$OSTYPE" == "darwin"* ]]; then
  if command -v brew &> /dev/null; then
    echo "Brew installed"
  else
    echo "Intstalling brew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

# Ensure dependencies are installed
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
