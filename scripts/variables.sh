#!/bin/bash

# Your name, once. The names below are built from it, like in infra/dev.bicepparam.
export NAME="murat"

# Azure Resource Group
export RESOURCE_GROUP="MuratBuyuksal"

# App Service Plan (the tier is set in infra/dev.bicepparam, not here)
export PLAN_NAME="asp-waypoint-$NAME"

# Web App
export APP_NAME="app-waypoint-$NAME"

# Managed identity for GitHub Actions
export IDENTITY_NAME="id-waypoint-pipeline-$NAME"

# Container registry Letters and digits only.
export REGISTRY_NAME="crwaypoint$NAME"

# Log Analytics workspace
export WORKSPACE_NAME="log-waypoint-$NAME"

# Display configuration
echo "Azure configuration loaded:"
echo "---------------------------"
echo "Name: $NAME"
echo "Resource Group: $RESOURCE_GROUP"
echo "App Service Plan: $PLAN_NAME"
echo "Web App: $APP_NAME"
echo "Identity: $IDENTITY_NAME"
echo "Registry: $REGISTRY_NAME"
echo "Workspace: $WORKSPACE_NAME"