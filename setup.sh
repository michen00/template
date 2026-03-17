#!/bin/bash

set -euo pipefail

TEMPLATE="$(pwd)"
MANIFEST="$TEMPLATE/manifest.txt"
QUIET="${SETUP_SH_QUIET:-0}"
MANIFEST_ENTRIES=()

quiet_echo() {
  if [ "$QUIET" != "1" ]; then
    echo "$1"
  fi
}

quiet_blank() {
  if [ "$QUIET" != "1" ]; then
    echo ""
  fi
}

read_input() {
  local __var="$1"
  local __prompt="$2"
  if [ "$QUIET" = "1" ]; then
    read -r "${__var:?}"
  else
    read -r -p "$__prompt" "${__var:?}"
  fi
}

escape_sed_pattern() {
  printf '%s' "$1" | sed 's/[.[\*^$/]/\\&/g'
}

escape_sed_replacement() {
  printf '%s' "$1" | sed 's/[&/\\]/\\&/g'
}

manifest_contains() {
  local candidate="$1"
  local entry

  for entry in "${MANIFEST_ENTRIES[@]}"; do
    if [[ "$entry" == "$candidate" ]]; then
      return 0
    fi
  done

  return 1
}

replace_template_tokens() {
  local project_dir="$1"
  local project_name="$2"
  local placeholder="__SETUP_SH_TEMPLATES__"
  local relative_path
  local file

  for relative_path in "${MANIFEST_ENTRIES[@]}"; do
    [ "$relative_path" = ".gitignore" ] && continue
    file="$project_dir/$relative_path"
    [ -f "$file" ] || continue

    # Force POSIX locale so BSD sed handles non-UTF8 bytes predictably, and avoid
    # touching the plural "templates" used in comments/documentation.
    if grep -Iql "template" "$file"; then
      LC_ALL=C sed -i.bak \
        -e "s/templates/$placeholder/g" \
        -e "s/template/$project_name/g" \
        -e "s/$placeholder/templates/g" \
        "$file" || return 1
    fi
  done

  return 0
}

replace_module_tokens() {
  local project_dir="$1"
  local module_name="$2"
  local placeholder="__SETUP_SH_MODULE_NAME__"
  local relative_path
  local file

  for relative_path in "${MANIFEST_ENTRIES[@]}"; do
    [ "$relative_path" = ".gitignore" ] && continue
    file="$project_dir/$relative_path"
    [ -f "$file" ] || continue

    if grep -Iql "$placeholder" "$file"; then
      LC_ALL=C sed -i.bak \
        -e "s/$placeholder/$module_name/g" \
        "$file" || return 1
    fi
  done

  return 0
}

fix_module_name_references() {
  local project_dir="$1"
  local project_name="$2"
  local module_name="$3"

  [ "$project_name" = "$module_name" ] && return 0

  local coveragerc="$project_dir/.coveragerc"
  if [ -f "$coveragerc" ]; then
    LC_ALL=C sed -i.bak \
      -e "s/^source_pkgs = ${project_name}$/source_pkgs = ${module_name}/" \
      "$coveragerc" || return 1
  fi

  local pyproject="$project_dir/pyproject.toml"
  if [ -f "$pyproject" ]; then
    LC_ALL=C sed -i.bak \
      -e "s/= '${project_name}\./= '${module_name}./" \
      "$pyproject" || return 1
  fi

  return 0
}

replace_profile_tokens() {
  local project_dir="$1"
  local owner_pat owner_rep author_pat author_rep email_pat email_rep
  local relative_path file

  owner_pat="$(escape_sed_pattern "$TMPL_GITHUB_OWNER")"
  owner_rep="$(escape_sed_replacement "$GITHUB_OWNER")"
  author_pat="$(escape_sed_pattern "$TMPL_AUTHOR_NAME")"
  author_rep="$(escape_sed_replacement "$AUTHOR_NAME")"
  email_pat="$(escape_sed_pattern "$TMPL_AUTHOR_EMAIL")"
  email_rep="$(escape_sed_replacement "$AUTHOR_EMAIL")"

  for relative_path in "${MANIFEST_ENTRIES[@]}"; do
    [ "$relative_path" = ".gitignore" ] && continue
    [ "$relative_path" = ".pre-commit-config.yaml" ] && continue
    file="$project_dir/$relative_path"
    [ -f "$file" ] || continue

    if grep -Iql "$TMPL_GITHUB_OWNER\|$TMPL_AUTHOR_NAME\|$TMPL_AUTHOR_EMAIL" "$file"; then
      LC_ALL=C sed -i.bak \
        -e "s/$owner_pat/$owner_rep/g" \
        -e "s/$author_pat/$author_rep/g" \
        -e "s/$email_pat/$email_rep/g" \
        "$file" || return 1
    fi
  done

  return 0
}

handle_cliff_email_swap() {
  local project_dir="$1"
  local cliff_file="$project_dir/cliff.toml"
  [ -f "$cliff_file" ] || return 0

  case "$CLIFF_EMAIL_SWAP" in
    keep) ;;
    reverse)
      local personal_toml_pat new_replace
      personal_toml_pat="$(printf '%s' "$TMPL_AUTHOR_EMAIL" | sed 's/[.]/\\./g')"
      new_replace="$(escape_sed_replacement "$AUTHOR_EMAIL")"
      LC_ALL=C sed -i.bak \
        -e 's/# Replace work email with personal email/# Replace personal email with work email/' \
        "$cliff_file" || return 1
      LC_ALL=C sed -i.bak \
        -e "/pattern = '.*@/s|.*|    { pattern = '${personal_toml_pat}', replace = \"${new_replace}\" },|" \
        "$cliff_file" || return 1
      ;;
    remove)
      LC_ALL=C sed -i.bak \
        -e '/# Replace work email with personal email/d' \
        -e "/pattern = '.*@/d" \
        "$cliff_file" || return 1
      ;;
  esac

  return 0
}

handle_deepwiki() {
  local project_dir="$1"
  local readme="$project_dir/.README.md"
  [ -f "$readme" ] || return 0

  if [ "$INCLUDE_DEEPWIKI" != "true" ]; then
    LC_ALL=C sed -i.bak \
      -e '/\[!\[Ask DeepWiki\]/d' \
      "$readme" || return 1
  fi

  return 0
}

disable_example_script() {
  local project_dir="$1"
  local pyproject="$project_dir/pyproject.toml"

  if [ -f "$pyproject" ]; then
    LC_ALL=C sed -i.bak \
      -e 's/^\[project\.scripts\]/# [project.scripts]/' \
      -e 's/^example-script = /# example-script = /' \
      "$pyproject" || return 1
  fi
  return 0
}

cleanup_backup_files() {
  local project_dir="$1"
  local relative_path

  for relative_path in "${MANIFEST_ENTRIES[@]}"; do
    rm -f "$project_dir/$relative_path.bak"
  done

  rm -f "$project_dir/pyproject.toml.bak"
  return 0
}

validate_project_name() {
  local __var="$1"
  local __name="$2"

  while true; do
    if [ -z "$__name" ]; then
      quiet_echo "Project name cannot be empty."
      read_input "$__var" "Enter a name for the project: "
      __name="${!__var}"
      continue
    fi
    if [[ $__name =~ [^a-zA-Z0-9_-] ]]; then
      quiet_echo "Project name can only contain letters, numbers, hyphens, and underscores."
      read_input "$__var" "Enter a name for the project: "
      __name="${!__var}"
      continue
    fi
    break
  done
  eval "$__var='$__name'"
}

derive_module_name() {
  local __var="$1"
  local __name="$2"
  local __module

  __module="$(printf '%s' "$__name" |
    tr '[:upper:]' '[:lower:]' |
    LC_ALL=C sed -E \
      -e 's/-+/_/g' \
      -e 's/[^a-z0-9_]/_/g' \
      -e 's/_+/_/g' \
      -e 's/^_+//' \
      -e 's/_+$//')"

  if [ -z "$__module" ]; then
    __module="project"
  fi

  if [[ $__module =~ ^[0-9] ]]; then
    __module="_$__module"
  fi

  eval "$__var='$__module'"
}

regenerate_gitignore() {
  local project_dir="$1"

  if [ "${SETUP_SH_SKIP_GITIGNORE:-0}" = "1" ]; then
    quiet_echo "Skipping .gitignore regeneration (SETUP_SH_SKIP_GITIGNORE=1)."
    return 0
  fi

  quiet_echo "Attempting to generate fresh .gitignore from GitHub templates..."

  if [ -f "$project_dir/scripts/concat-gitignores.sh" ]; then
    if (cd "$project_dir" && bash scripts/concat-gitignores.sh > /dev/null 2>&1); then
      quiet_echo "✓ Generated fresh .gitignore from upstream templates"
    else
      quiet_echo "⚠ Failed to fetch templates (network issue?). Using static .gitignore as fallback."
    fi
  else
    quiet_echo "⚠ concat-gitignores.sh script not found. Using static .gitignore."
  fi

  return 0
}

finalize_setup() {
  local project_dir="$1"
  local project_name="$2"
  local module_name="$3"

  cd "$project_dir" || return 1
  replace_template_tokens "$project_dir" "$project_name" || return 1
  replace_module_tokens "$project_dir" "$module_name" || return 1
  fix_module_name_references "$project_dir" "$project_name" "$module_name" || return 1
  replace_profile_tokens "$project_dir" || return 1
  handle_cliff_email_swap "$project_dir" || return 1
  handle_deepwiki "$project_dir" || return 1
  disable_example_script "$project_dir" || return 1
  cleanup_backup_files "$project_dir" || return 1
  mv .README.md README.md || return 1
  mv .github/.copilot-instructions.md .github/copilot-instructions.md || return 1
  mv .AGENTS.md AGENTS.md || return 1
  mv .CLAUDE.md CLAUDE.md || return 1
  mv .specify/memory/.constitution.md .specify/memory/constitution.md || return 1
  mv src/template "src/$module_name" || return 1
  regenerate_gitignore "$project_dir" || return 1
  : > .git-blame-ignore-revs || return 1
  quiet_echo "Project set up successfully in $PROJECT."
  return 0
}

# Verify manifest exists
if [ ! -r "$MANIFEST" ]; then
  echo "$MANIFEST cannot be read. Exiting script."
  exit 1
fi

while IFS= read -r FILE; do
  [ -n "$FILE" ] || continue
  MANIFEST_ENTRIES+=("$FILE")
done < "$MANIFEST"

# Parse --profile flag
PROFILE_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      if [ -z "${2:-}" ]; then
        echo "Error: --profile requires a profile name." >&2
        exit 1
      fi
      PROFILE_NAME="$2"
      shift 2
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Source owner profile configuration
PROFILE_FILE="$TEMPLATE/.template-profile.sh"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "Error: $PROFILE_FILE not found." >&2
  exit 1
fi
# shellcheck source=.template-profile.sh
source "$PROFILE_FILE"

if [ -n "$PROFILE_NAME" ]; then
  fn="profile_${PROFILE_NAME}"
  if ! type "$fn" > /dev/null 2>&1; then
    echo "Error: profile '$PROFILE_NAME' is not defined in $PROFILE_FILE" >&2
    exit 1
  fi
  "$fn"
fi

CLIFF_EMAIL_SWAP="${CLIFF_EMAIL_SWAP:-remove}"
INCLUDE_DEEPWIKI="${INCLUDE_DEEPWIKI:-true}"

# Ask user where to set up the project
quiet_echo "Where would you like to set up your project?"
quiet_echo "1) Current directory (will remove files not in manifest)"
quiet_echo "2) New directory"
read_input SETUP_CHOICE "Enter choice (1 or 2): "

if [[ $SETUP_CHOICE == "1" ]]; then
  # === CURRENT DIRECTORY SETUP ===

  # Get and validate project name (default to current directory name)
  DEFAULT_NAME="$(basename "$(pwd)")"
  if [ "$DEFAULT_NAME" = "template" ]; then
    DEFAULT_NAME=""
  fi
  if [ -n "$DEFAULT_NAME" ]; then
    read_input PROJECTNAME "Enter a name for the project [$DEFAULT_NAME]: "
    [ -z "$PROJECTNAME" ] && PROJECTNAME="$DEFAULT_NAME"
  else
    read_input PROJECTNAME "Enter a name for the project: "
  fi
  validate_project_name PROJECTNAME "$PROJECTNAME"
  derive_module_name MODULENAME "$PROJECTNAME"

  PROJECT="$TEMPLATE"

  # Show what will be removed
  quiet_blank
  quiet_echo "The following files will be REMOVED (not in manifest):"

  # Find files to remove
  TO_REMOVE=()
  while IFS= read -r -d '' FILE; do
    FILE_REL="${FILE#./}"

    if [[ $FILE_REL == ".git" ]] || [[ $FILE_REL == .git/* ]]; then
      continue
    fi

    if [[ $FILE_REL == "setup.sh" ]] || [[ $FILE_REL == "manifest.txt" ]]; then
      TO_REMOVE+=("$FILE_REL")
      quiet_echo "  - $FILE_REL"
      continue
    fi

    if ! manifest_contains "$FILE_REL"; then
      TO_REMOVE+=("$FILE_REL")
      quiet_echo "  - $FILE_REL"
    fi
  done < <(find . -mindepth 1 \( -type f -o -type l \) -print0)

  quiet_echo "Total files to remove: ${#TO_REMOVE[@]}"

  quiet_blank
  read_input CONFIRM "Continue with setup? This will DELETE the files listed above. (y/n): "

  if [ "$CONFIRM" != "y" ]; then
    quiet_echo "Setup cancelled. No changes made."
    exit 0
  fi

  # Remove non-manifest files
  for FILE in "${TO_REMOVE[@]}"; do
    rm -f "$FILE"
  done

  find . -depth -type d -empty -not -path "." -not -path "./.git" -not -path "./.git/*" -delete

  if [ -e .git ]; then
    read_input KEEP_GIT "Existing .git directory found. Keep it? (y = preserve history/remote, n = start fresh): "
    if [ "$KEEP_GIT" != "y" ]; then
      rm -rf .git
    fi
  fi

  finalize_setup "$PROJECT" "$PROJECTNAME" "$MODULENAME" || exit 1

  if [ ! -e "$PROJECT/.git" ]; then
    git init "$PROJECT" > /dev/null 2>&1
    quiet_echo "Initialized new git repository in $PROJECT."
  fi

elif [[ $SETUP_CHOICE == "2" ]]; then
  # === NEW DIRECTORY SETUP ===

  # Get and validate project name
  read_input PROJECTNAME "Enter a name for the project: "
  validate_project_name PROJECTNAME "$PROJECTNAME"
  derive_module_name MODULENAME "$PROJECTNAME"

  PROJECT="$(cd "$TEMPLATE" && cd .. && pwd)/$PROJECTNAME"

  if [ -d "$PROJECT" ]; then
    quiet_echo "Directory $PROJECT already exists."
    read_input OVERWRITE "Do you want to overwrite it? (y/n): "

    if [ "$OVERWRITE" != "y" ]; then
      quiet_echo "Setup cancelled. No changes made."
      exit 0
    fi

    quiet_echo "Overwriting directory $PROJECT..."
    rm -rf "$PROJECT"
  fi

  # Copy manifest files to new directory
  for FILE in "${MANIFEST_ENTRIES[@]}"; do
    SRC_PATH="$TEMPLATE/$FILE"
    DEST_DIR="$PROJECT/$(dirname "$FILE")"
    mkdir -p "$DEST_DIR"
    if [ -e "$SRC_PATH" ]; then
      cp -r "$SRC_PATH" "$DEST_DIR"
    else
      echo "Warning: $FILE listed in manifest but missing." >&2
    fi
  done

  finalize_setup "$PROJECT" "$PROJECTNAME" "$MODULENAME" || exit 1

  if [ ! -e "$PROJECT/.git" ]; then
    git init "$PROJECT" > /dev/null 2>&1
    quiet_echo "Initialized new git repository in $PROJECT."
  fi

else
  quiet_echo "Invalid choice. Exiting script."
  exit 1
fi

quiet_echo "Project setup complete. Happy coding!"
exit 0
