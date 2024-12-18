#!/bin/bash

TEMPLATE="$(pwd)"
CWD=$(basename "$TEMPLATE")

MANIFEST="$TEMPLATE/manifest.txt"

cat "$MANIFEST" > /dev/null 2>&1 || { echo "$MANIFEST cannot be read. Exiting script."; exit 1; }

while true; do
    while true; do
        read -pr "Enter a name for the project: " PROJECTNAME

        if [ -z "$PROJECTNAME" ]; then
            echo "Project name cannot be empty."
            continue
        fi
        if [[ "$PROJECTNAME" =~ [^a-zA-Z0-9_-] ]]; then
            echo "Project name can only contain letters, numbers, hyphens, and underscores."
            continue
        fi
        break
    done

    PROJECT="$(cd "$TEMPLATE" && cd .. && pwd)/$PROJECTNAME"

    if [ -d "$PROJECT" ]; then
        echo "Directory $PROJECT exists."
        if [ "$PROJECTNAME" == "$CWD" ]; then
            echo "Project name cannot be '$CWD'."
            continue
        fi

        read -pr "Do you want to overwrite the directory? (y/n): " OVERWRITE

        if [ "$OVERWRITE" == "y" ]; then
            echo "Overwriting directory $PROJECT..."
            rm -rf "$PROJECT"
        else
            echo "No changes made. Exiting script."
            exit 1
        fi
    fi
    break
done

while read -r FILE; do
    mkdir -p "$(dirname "$PROJECT/$FILE")"
    cp -r "$TEMPLATE/$FILE" "$PROJECT/$(dirname "$FILE")"
done < "$MANIFEST"

cd "$PROJECT" \
&& rm -rf .git \
&& mv README_template.md README.md \
&& mv src/template "src/$PROJECTNAME" \
&& sed -i.bak "s/template/$PROJECTNAME/g" "$(find "$PROJECT" -type f -exec grep -l "template" {} +)" \
&& find . -name "*.bak" -type f -delete \
&& if command -v poetry &> /dev/null; then
    cd "$PROJECT" && poetry update
fi \
&& echo "Project created successfully in $PROJECT." \
&& read -pr "Do you want to initialize a new Git repository in $PROJECT? (y/n): " INIT_GIT

if [ "$INIT_GIT" == y ]; then
    read -pr "Enter your GitHub username: " GITHUB_USERNAME
    GITHUB_REPO_URL="https://github.com/$GITHUB_USERNAME/$PROJECTNAME.git"
    git config --global init.defaultBranch main

    cd "$PROJECT" \
    && if ! git init; then
        echo "Error: Git init failed. Exiting script."
        exit 1
    else
        echo "Git repository initialized in $PROJECT"
    fi

    cd "$PROJECT" \
    && git remote add origin "git@github.com:$GITHUB_USERNAME/$PROJECTNAME.git" \
    && git add . \
    && git commit -m "Update template" \
    && git pull origin main --rebase -X theirs \
    && rm manifest.txt README_template.md setup.sh; rm -rf src/template \
    && git add . \
    && git commit --amend --no-edit \
    && if ! git push -u origin main; then
        echo "Error: Git push failed. Exiting script."
        exit 1
    else
        echo "Project pushed to GitHub repository: $GITHUB_REPO_URL"
    fi
fi

echo "Project setup complete. Happy coding!"
exit 0
