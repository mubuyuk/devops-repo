#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking the scripts"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "ShellCheck is not installed here, so this step is skipped. The pipeline runs it."
fi

echo "==> Installing the dependencies"
npm ci

echo "Build OK"
