#!/usr/bin/env bash
# Packages the latest commit of Waypoint and deploys it to App Service.
# Usage: ./scripts/deploy-app-service.sh app-waypoint-name rg-waypoint-name
set -euo pipefail

app_name="${1:?Give the name of the web app as the first argument}"
resource_group="${2:?Give the name of the resource group as the second argument}"
commit=$(git rev-parse HEAD)

echo "==> Packaging commit $commit"
mkdir -p artifacts
git archive \
  --format=zip \
  --output=artifacts/app.zip \
  --add-virtual-file="src/commit.txt:$commit" \
  HEAD package.json package-lock.json src

echo "==> Deploying to App Service: $app_name"
az webapp deploy \
  --name "$app_name" \
  --resource-group "$resource_group" \
  --src-path artifacts/app.zip \
  --type zip \
  --track-status false \
  --output none

# Azure's own status sometimes says "Starting the site" for minutes after the app is up.
# The smoke test asks the app itself for the new commit instead.
echo "==> Uploaded. The health check confirms the new version."
