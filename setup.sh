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

validate_owner() {
  local __owner="$1"
  if [ -z "$__owner" ]; then
    echo "Owner cannot be empty." >&2
    return 1
  fi
  if [[ $__owner =~ [^a-zA-Z0-9_-] ]]; then
    echo "Owner can only contain letters, numbers, hyphens, and underscores." >&2
    return 1
  fi
  return 0
}

validate_profile() {
  local __profile="$1"
  if [ "$__profile" != "public" ] && [ "$__profile" != "private" ]; then
    echo "Profile must be exactly 'public' or 'private'." >&2
    return 1
  fi
  return 0
}

replace_owner_tokens() {
  local project_dir="$1"
  local project_name="$2"
  local owner="$3"
  local files

  files=$(
    find "$project_dir" -type f -exec grep -Il "michen00/$project_name" {} + 2> /dev/null || true
  )

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    LC_ALL=C sed -i.bak \
      "s|michen00/$project_name|$owner/$project_name|g" \
      "$file" || return 1
  done <<< "$files"

  return 0
}

remove_personal_postprocessor() {
  local project_dir="$1"
  local cliff_path="$project_dir/cliff.toml"

  if [ -f "$cliff_path" ]; then
    LC_ALL=C sed -i.bak \
      '/michael\.chen@aicadium\.ai/d' \
      "$cliff_path" || return 1
  fi
  return 0
}

replace_author_metadata() {
  local project_dir="$1"
  local owner="$2"
  local pyproject="$project_dir/pyproject.toml"

  if [ -f "$pyproject" ]; then
    LC_ALL=C sed -i.bak \
      "s|^authors = .*|authors = [{ name = \"$owner\" }]|" \
      "$pyproject" || return 1
  fi
  return 0
}

replace_coc_email() {
  local project_dir="$1"
  local coc_path="$project_dir/CODE_OF_CONDUCT.md"

  if [ -f "$coc_path" ]; then
    LC_ALL=C sed -i.bak \
      's|\[michael\.chen\.0@gmail\.com\](mailto:michael\.chen\.0@gmail\.com)|[INSERT CONTACT EMAIL]|g' \
      "$coc_path" || return 1
  fi
  return 0
}

regenerate_gitignore() {
  local project_dir="$1"

  # Try to regenerate .gitignore using the concat script
  quiet_echo "Attempting to generate fresh .gitignore from GitHub templates..."

  if [ -f "$project_dir/.github/scripts/concat_gitignores.sh" ]; then
    if (cd "$project_dir" && bash .github/scripts/concat_gitignores.sh > /dev/null 2>&1); then
      quiet_echo "✓ Generated fresh .gitignore from upstream templates"
    else
      quiet_echo "⚠ Failed to fetch templates (network issue?). Using static .gitignore as fallback."
    fi
  else
    quiet_echo "⚠ concat_gitignores.sh script not found. Using static .gitignore."
  fi

  # Always return success so setup continues regardless
  return 0
}

finalize_setup() {
  local project_dir="$1"
  local project_name="$2"
  local owner="$3"
  local profile="$4"

  cd "$project_dir" &&
    mv .README.md README.md &&
    mv .github/.copilot-instructions.md .github/copilot-instructions.md &&
    mv .AGENTS.md AGENTS.md &&
    mv .CLAUDE.md CLAUDE.md &&
    mv src/template "src/$project_name" &&
    replace_template_tokens "$project_dir" "$project_name" &&
    replace_owner_tokens "$project_dir" "$project_name" "$owner" &&
    remove_personal_postprocessor "$project_dir" &&
    replace_author_metadata "$project_dir" "$owner" &&
    replace_coc_email "$project_dir" &&
    disable_example_script "$project_dir" &&
    if [ "$profile" = "private" ]; then apply_private_profile "$project_dir"; fi &&
    regenerate_gitignore "$project_dir" &&
    find "$project_dir" -name "*.bak" -type f -delete &&
    echo "" > .git-blame-ignore-revs &&
    quiet_echo "Project set up successfully in $PROJECT."
}

should_skip_for_profile() {
  local filename="$1"
  local profile="$2"

  local private_skip_list=(
    ".github/workflows/greet-new-contributors.yml"
  )

  if [ "$profile" = "private" ]; then
    for skip_file in "${private_skip_list[@]}"; do
      if [ "$filename" = "$skip_file" ]; then
        return 0
      fi
    done
  fi
  return 1
}

apply_private_profile() {
  local project_dir="$1"
  local readme_path="$project_dir/README.md"

  if [ -f "$readme_path" ]; then
    LC_ALL=C sed -i.bak \
      '/\[!\[Ask DeepWiki\]/d' \
      "$readme_path" || return 1
  fi
  return 0
}

# Verify manifest exists
cat "$MANIFEST" > /dev/null 2>&1 || {
  echo "$MANIFEST cannot be read. Exiting script."
  exit 1
}

# --- CLI flag parsing ---
owner=""
profile=""

while (($#)); do
  case "$1" in
    --owner=*)
      owner="${1#--owner=}"
      if ! validate_owner "$owner" 2> /dev/null; then
        owner=""
      fi
      ;;
    --profile=*)
      profile="${1#--profile=}"
      if ! validate_profile "$profile" 2> /dev/null; then
        profile=""
      fi
      ;;
    *)
      break
      ;;
  esac
  shift
done

# --- Interactive prompts ---

# 1. Setup location
quiet_echo "Where would you like to set up your project?"
quiet_echo "1) Current directory (will remove files not in manifest)"
quiet_echo "2) New directory"
read_input SETUP_CHOICE "Enter choice (1 or 2): "

# 2. Project name
read_input PROJECTNAME "Enter a name for the project: "
validate_project_name PROJECTNAME "$PROJECTNAME"

# 3. GitHub owner (skip if set via --owner flag)
if [ -z "$owner" ]; then
  while true; do
    read_input owner "GitHub owner (user or org): "
    if [ -z "$owner" ]; then
      quiet_echo "Owner cannot be empty."
      continue
    fi
    if [[ $owner =~ [^a-zA-Z0-9_-] ]]; then
      quiet_echo "Owner can only contain letters, numbers, hyphens, and underscores."
      owner=""
      continue
    fi
    break
  done
fi

# 4. Profile selection (skip if set via --profile flag)
if [ -z "$profile" ]; then
  while true; do
    quiet_echo "Select project profile:"
    quiet_echo "1) Public (includes all community features)"
    quiet_echo "2) Private (excludes public-only features)"
    read_input PROFILE_CHOICE "Enter choice (1 or 2): "
    case "$PROFILE_CHOICE" in
      1)
        profile="public"
        break
        ;;
      2)
        profile="private"
        break
        ;;
      *) quiet_echo "Invalid choice. Please enter 1 or 2." ;;
    esac
  done
fi

# --- Branch on setup location ---

if [[ $SETUP_CHOICE == "1" ]]; then
  # === CURRENT DIRECTORY SETUP ===

  PROJECT="$TEMPLATE"

  # Show what will be removed
  quiet_blank
  quiet_echo "The following files will be REMOVED (not in manifest):"

  # Build list of files to keep (from manifest) and files to remove (profile-skipped)
  KEEP_FILES=()
  PROFILE_SKIP_FILES=()
  while IFS= read -r FILE; do
    if should_skip_for_profile "$FILE" "$profile"; then
      PROFILE_SKIP_FILES+=("$FILE")
      continue
    fi
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

  # Remove profile-skipped files that live inside kept directories
  for FILE in "${PROFILE_SKIP_FILES[@]}"; do
    rm -f "$FILE"
  done

  finalize_setup "$PROJECT" "$PROJECTNAME" "$owner" "$profile"

elif [[ $SETUP_CHOICE == "2" ]]; then
  # === NEW DIRECTORY SETUP ===

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
    should_skip_for_profile "$FILE" "$profile" && continue
    SRC_PATH="$TEMPLATE/$FILE"
    DEST_DIR="$PROJECT/$(dirname "$FILE")"
    mkdir -p "$DEST_DIR"
    if [ -e "$SRC_PATH" ]; then
      cp -r "$SRC_PATH" "$DEST_DIR"
    else
      echo "Warning: $FILE listed in manifest but missing." >&2
    fi
  done < "$MANIFEST"

  finalize_setup "$PROJECT" "$PROJECTNAME" "$owner" "$profile"

else
  quiet_echo "Invalid choice. Exiting script."
  exit 1
fi

quiet_echo "Project setup complete. Happy coding!"
exit 0
