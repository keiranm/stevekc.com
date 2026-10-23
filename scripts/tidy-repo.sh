#!/usr/bin/env bash
# Run once from the repo root, then commit.
set -e
# leaked/expired test output (contains temporary AWS credentials in a presigned form)
git rm -q --ignore-unmatch out.json msg-out.json lambda_test.json lambda_test.html
# deleted from AWS on 2026-10-14
git rm -q --ignore-unmatch lambda/inbox_whoami.py
# stray, backup and test files
git rm -q --ignore-unmatch file_me/fileme.html.bak lambda.py mountain_picture.jpeg .DS_Store
# vendored Pillow (rebuild instructions are in layer/README.md)
git rm -r -q --cached --ignore-unmatch layer/python layer/pillow-layer.zip
cat >> .gitignore <<'IGN'

# AWS CLI output and local build artefacts
out.json
*-out.json
*.zip
layer/python/
IGN
git add .gitignore README.md docs layer/README.md scripts
echo "done: review with git status, then commit"
