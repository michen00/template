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

regenerate_gitignore() {
  local project_dir="$1"

  # Try to regenerate .gitignore using the concat script
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

  # Always return success so setup continues regardless
  return 0
}

finalize_setup() {
  local project_dir="$1"
  local project_name="$2"

  cd "$project_dir" || return 1
  replace_template_tokens "$project_dir" "$project_name" || return 1
  disable_example_script "$project_dir" || return 1
  cleanup_backup_files "$project_dir" || return 1
  mv .README.md README.md || return 1
  mv .github/.copilot-instructions.md .github/copilot-instructions.md || return 1
  mv .AGENTS.md AGENTS.md || return 1
  mv .CLAUDE.md CLAUDE.md || return 1
  mv .specify/memory/.constitution.md .specify/memory/constitution.md || return 1
  mv src/template "src/$project_name" || return 1
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

  finalize_setup "$PROJECT" "$PROJECTNAME" || exit 1

  if [ ! -e "$PROJECT/.git" ]; then
    git init "$PROJECT" > /dev/null 2>&1
    quiet_echo "Initialized new git repository in $PROJECT."
  fi

elif [[ $SETUP_CHOICE == "2" ]]; then
  # === NEW DIRECTORY SETUP ===

  # Get and validate project name
  read_input PROJECTNAME "Enter a name for the project: "
  validate_project_name PROJECTNAME "$PROJECTNAME"

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

  finalize_setup "$PROJECT" "$PROJECTNAME" || exit 1

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
