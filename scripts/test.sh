#!/usr/bin/env bash
set -uo pipefail

fail=0

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ok    $name"
  else
    echo "  FAIL  $name"
    fail=1
  fi
}

echo "==> Checking the repo"
check "README.md exists"         test -f README.md
check ".gitignore exists"        test -f .gitignore
check "build.sh is executable"   test -x scripts/build.sh
check "README.md has a heading"  grep -q "^# " README.md

exit "$fail"
