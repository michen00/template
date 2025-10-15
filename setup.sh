#!/bin/bash

TEMPLATE="$(pwd)"
MANIFEST="$TEMPLATE/manifest.txt"

rename_workflow_copilot_file() {
  local root_dir="$1"
  local hidden_file="$root_dir/.github/workflows/.copilot-instructions.md"
  local target_file="$root_dir/.github/workflows/copilot-instructions.md"

  if [ -f "$hidden_file" ]; then
    mv "$hidden_file" "$target_file" || return 1
  fi

  return 0
}

replace_template_tokens() {
  local search_root="$1"
  local project_name="$2"
  local files

  files=$(
    find "$search_root" -type f -not -name ".gitignore" -exec grep -l "template" {} + 2> /dev/null || true
  )

  if [ -z "$files" ]; then
    return 0
  fi

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    sed -i.bak "s/template/$project_name/g" "$file" || return 1
  done <<< "$files"

  return 0
}

# Verify manifest exists
cat "$MANIFEST" > /dev/null 2>&1 || {
  echo "$MANIFEST cannot be read. Exiting script."
  exit 1
}

# Ask user where to set up the project
echo "Where would you like to set up your project?"
echo "1) Current directory (will remove files not in manifest)"
echo "2) New directory"
read -r -p "Enter choice (1 or 2): " SETUP_CHOICE

if [ "$SETUP_CHOICE" == "1" ]; then
  # === CURRENT DIRECTORY SETUP ===

  # Get project name
  while true; do
    read -r -p "Enter a name for the project: " PROJECTNAME

    if [ -z "$PROJECTNAME" ]; then
      echo "Project name cannot be empty."
      continue
    fi
    if [[ $PROJECTNAME =~ [^a-zA-Z0-9_-] ]]; then
      echo "Project name can only contain letters, numbers, hyphens, and underscores."
      continue
    fi
    break
  done

  PROJECT="$TEMPLATE"

  # Show what will be removed
  echo ""
  echo "The following files will be REMOVED (not in manifest):"

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
      if [[ $FILE_REL == "$KEEP" ]] || [[ $FILE_REL == "$KEEP"/* ]]; then
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
      echo "  - $FILE_REL"
    fi
  done < <(find . -mindepth 1 -maxdepth 1 -print0)

  echo ""
  read -r -p "Continue with setup? This will DELETE the files listed above. (y/n): " CONFIRM

  if [ "$CONFIRM" != "y" ]; then
    echo "Setup cancelled. No changes made."
    exit 0
  fi

  # Remove non-manifest files
  for FILE in "${TO_REMOVE[@]}"; do
    rm -rf "$FILE"
  done

  # Transform template files
  mv README_template.md README.md &&
    mv src/template "src/$PROJECTNAME" &&
    rename_workflow_copilot_file "$PROJECT" &&
    replace_template_tokens "$PROJECT" "$PROJECTNAME" &&
    find "$PROJECT" -name "*.bak" -type f -delete &&
    echo "Project set up successfully in $PROJECT."

elif [ "$SETUP_CHOICE" == "2" ]; then
  # === NEW DIRECTORY SETUP ===

  # Get project name and validate directory doesn't exist
  while true; do
    while true; do
      read -r -p "Enter a name for the project: " PROJECTNAME

      if [ -z "$PROJECTNAME" ]; then
        echo "Project name cannot be empty."
        continue
      fi
      if [[ $PROJECTNAME =~ [^a-zA-Z0-9_-] ]]; then
        echo "Project name can only contain letters, numbers, hyphens, and underscores."
        continue
      fi
      break
    done

    PROJECT="$(cd "$TEMPLATE" && cd .. && pwd)/$PROJECTNAME"

    if [ -d "$PROJECT" ]; then
      echo "Directory $PROJECT already exists."
      read -r -p "Do you want to overwrite it? (y/n): " OVERWRITE

      if [ "$OVERWRITE" == "y" ]; then
        echo "Overwriting directory $PROJECT..."
        rm -rf "$PROJECT"
        break
      else
        echo "Please choose a different name."
        continue
      fi
    fi
    break
  done

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

  # Transform template files
  cd "$PROJECT" &&
    mv README_template.md README.md &&
    mv src/template "src/$PROJECTNAME" &&
    rename_workflow_copilot_file "$PROJECT" &&
    replace_template_tokens "$PROJECT" "$PROJECTNAME" &&
    find "$PROJECT" -name "*.bak" -type f -delete &&
    echo "Project created successfully in $PROJECT."

else
  echo "Invalid choice. Exiting script."
  exit 1
fi

echo "Project setup complete. Happy coding!"
exit 0
