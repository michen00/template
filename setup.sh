#!/bin/bash

TEMPLATE="$(dirname "${BASH_SOURCE[0]}")"
MANIFEST="$TEMPLATE/manifest.txt"

cat "$MANIFEST" > /dev/null 2>&1 || { echo "$MANIFEST cannot be read. Exiting script."; exit 1; }

read -p "Enter a name for the project: " PROJECTNAME

PROJECT="$(cd "$TEMPLATE" && cd .. && pwd)/$PROJECTNAME"

if [ -d "$PROJECT" ]; then
    echo "Directory $PROJECT exists."
    read -p "Do you want to overwrite the directory? (y/n): " OVERWRITE

    if [ "$OVERWRITE" == "y" ]; then
        echo "Overwriting directory $PROJECT..."
        rm -rf "$PROJECT"
    else
        echo "No changes made. Exiting script."
        exit 1
    fi
fi

while read -r FILE; do
    mkdir -p "$(dirname "$PROJECT/$FILE")"
    cp -r "$TEMPLATE/$FILE" "$PROJECT/$(dirname "$FILE")"
done < "$MANIFEST"

cd "$PROJECT" \
&& rm -rf ".git" \
&& mv README_template.md README.md \
&& mv "src/template" "src/$PROJECTNAME" \
&& sed -i.bak "s/template/$PROJECTNAME/g" $(find "$PROJECT" -type f -exec grep -l "template" {} +) \
&& find . -name "*.bak" -type f -delete \
&& echo "Project created successfully in $PROJECT." \
&& read -p "Do you want to initialize a new Git repository in $PROJECT? (y/n): " INIT_GIT

if [ "$INIT_GIT" == "y" ]; then

    GITHUB_USERNAME="michen00"
    GITHUB_REPO_URL="https://github.com/$GITHUB_USERNAME/$PROJECTNAME.git"

    cd "$PROJECT" && git init \
    && echo "Git repository initialized in $PROJECT"
    if [ $? -ne 0 ]; then
        echo "Error: Git init failed. Exiting script."
        exit 1
    fi

    git remote add origin "$GITHUB_REPO_URL" \
    && git add . \
    && git commit -m "Initial commit from template" \
    && git push -u origin main \
    && echo "Project pushed to GitHub repository: $GITHUB_REPO_URL"
    if [ $? -ne 0 ]; then
        echo "Error: Git push incomplete. Exiting script."
        exit 1
    fi
fi

echo "Project setup complete. Happy coding!"
exit 0
