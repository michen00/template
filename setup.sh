#!/bin/bash

# TODO: refactor

TEMPLATE="$(pwd)"
MANIFEST="$TEMPLATE/manifest.txt"
QUIET="${SETUP_SH_QUIET:-0}"

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

replace_template_tokens() {
  local search_root="$1"
  local project_name="$2"
  local placeholder="__SETUP_SH_TEMPLATES__"
  local files

  # Find files that contain the literal "template". Exclude the top-level
  # `.gitignore` in the template root (we don't want to rewrite that file),
  # and avoid matching binary files by asking grep to ignore binaries.
  files=$(
    find "$search_root" -type f -not -path "$search_root/.gitignore" -exec grep -Il "template" {} + 2> /dev/null || true
  )

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # Force POSIX locale so BSD sed handles non-UTF8 bytes predictably, and avoid
    # touching the plural "templates" used in comments/documentation.
    LC_ALL=C sed -i.bak \
      -e "s/templates/$placeholder/g" \
      -e "s/template/$project_name/g" \
      -e "s/$placeholder/templates/g" \
      "$file" || return 1
  done <<< "$files"

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

finalize_setup() {
  local project_dir="$1"
  local project_name="$2"

  cd "$project_dir" &&
    mv README_template.md README.md &&
    mv .github/.copilot-instructions.md .github/copilot-instructions.md &&
    mv .AGENTS.md AGENTS.md &&
    mv src/template "src/$project_name" &&
    replace_template_tokens "$project_dir" "$project_name" &&
    disable_example_script "$project_dir" &&
    find "$project_dir" -name "*.bak" -type f -delete &&
    echo "" > .git-blame-ignore-revs &&
    quiet_echo "Project set up successfully in $PROJECT."
}

# Verify manifest exists
cat "$MANIFEST" > /dev/null 2>&1 || {
  echo "$MANIFEST cannot be read. Exiting script."
  exit 1
}

# Ask user where to set up the project
quiet_echo "Where would you like to set up your project?"
quiet_echo "1) Current directory (will remove files not in manifest)"
quiet_echo "2) New directory"
read_input SETUP_CHOICE "Enter choice (1 or 2): "

if [[ $SETUP_CHOICE == "1" ]]; then
  # === CURRENT DIRECTORY SETUP ===

  # Get and validate project name
  read_input PROJECTNAME "Enter a name for the project: "
  validate_project_name PROJECTNAME "$PROJECTNAME"

  PROJECT="$TEMPLATE"

  # Show what will be removed
  quiet_blank
  quiet_echo "The following files will be REMOVED (not in manifest):"

  # Build list of files to keep (from manifest)
  KEEP_FILES=()
  while IFS= read -r FILE; do
    KEEP_FILES+=("$FILE")
  done < "$MANIFEST"

  # Always keep .git directory if it exists
  KEEP_FILES+=(".git")

  # Find files to remove
  TO_REMOVE=()
  while IFS= read -r -d '' FILE; do
    FILE_REL="${FILE#./}"

    # Skip if it's in manifest
    SHOULD_KEEP=false
    for KEEP in "${KEEP_FILES[@]}"; do
      if [[ $KEEP == "$FILE_REL" ]] || [[ $KEEP == "$FILE_REL"/* ]]; then
        SHOULD_KEEP=true
        break
      fi
    done

    # Always remove setup files
    if [[ $FILE_REL == "setup.sh" ]] || [[ $FILE_REL == "manifest.txt" ]]; then
      SHOULD_KEEP=false
    fi

    if ! $SHOULD_KEEP; then
      TO_REMOVE+=("$FILE_REL")
      quiet_echo "  - $FILE_REL"
    fi
  done < <(find . -mindepth 1 -maxdepth 1 -print0)

  quiet_blank
  read_input CONFIRM "Continue with setup? This will DELETE the files listed above. (y/n): "

  if [ "$CONFIRM" != "y" ]; then
    quiet_echo "Setup cancelled. No changes made."
    exit 0
  fi

  # Remove non-manifest files
  for FILE in "${TO_REMOVE[@]}"; do
    rm -rf "$FILE"
  done

  finalize_setup "$PROJECT" "$PROJECTNAME"

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
  while IFS= read -r FILE; do
    [ -n "$FILE" ] || continue
    SRC_PATH="$TEMPLATE/$FILE"
    DEST_DIR="$PROJECT/$(dirname "$FILE")"
    mkdir -p "$DEST_DIR"
    if [ -e "$SRC_PATH" ]; then
      cp -r "$SRC_PATH" "$DEST_DIR"
    else
      echo "Warning: $FILE listed in manifest but missing." >&2
    fi
  done < "$MANIFEST"

  finalize_setup "$PROJECT" "$PROJECTNAME"

else
  quiet_echo "Invalid choice. Exiting script."
  exit 1
fi

quiet_echo "Project setup complete. Happy coding!"
exit 0
