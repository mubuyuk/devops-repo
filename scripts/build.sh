#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking the scripts"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "ShellCheck is not installed here, so this step is skipped. The pipeline runs it."
fi

echo "==> Checking that the repo's files exist"
for file in README.md .gitignore; do
  test -f "$file" || { echo "Missing: $file"; exit 1; }
done

echo "Build OK"
