#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used by setup.sh which sources this file.
# Owner profile configuration for template setup.
#
# Regular users: edit the default values below, then run setup.sh.
# Template author: run  setup.sh --profile <name>  to use a named profile.
#
# TMPL_* constants must match what is currently in the template source files.
# Only change these if you have also updated the corresponding source files.

TMPL_GITHUB_OWNER="michen00"
TMPL_AUTHOR_NAME="Michael I Chen"
TMPL_AUTHOR_EMAIL="michael.chen.0@gmail.com"

# --- Default values (edit these) ---
GITHUB_OWNER="michen00"
AUTHOR_NAME="Michael I Chen"
AUTHOR_EMAIL="michael.chen.0@gmail.com"

# --- Named profiles (activated via: setup.sh --profile <name>) ---

profile_personal() {
  GITHUB_OWNER="michen00"
  AUTHOR_NAME="Michael I Chen"
  AUTHOR_EMAIL="michael.chen.0@gmail.com"
  CLIFF_EMAIL_SWAP="keep"
  INCLUDE_DEEPWIKI=true
}

profile_work() {
  GITHUB_OWNER="aicadium-ai"
  AUTHOR_NAME="Michael Chen"
  AUTHOR_EMAIL="michael.chen@aicadium.ai"
  CLIFF_EMAIL_SWAP="reverse"
  INCLUDE_DEEPWIKI=false
}
