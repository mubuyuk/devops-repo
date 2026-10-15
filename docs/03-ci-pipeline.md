# CI pipeline

## What the scripts do
One sentence each for build.sh and test.sh.
build.sh - checks if the files in the repo exists, README.md and .gitignore
test.sh - it collects results, reports each check individually, and returns a single exit code.

## The failure the pipeline caught
What I broke on purpose, and what the pipeline said. A link to the red run is enough.
I removed the .gitignore file on purpose. The result:

Run ./scripts/build.sh
==> Checking the scripts
==> Checking that the repo's files exist
Missing: .gitignore
Error: Process completed with exit code 1.