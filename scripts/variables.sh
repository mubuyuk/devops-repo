#!/bin/bash

# Azure Resource Group
export RESOURCE_GROUP="RG-muratbuyuksal"

# App Service Plan
export PLAN_NAME="asp-waypoint-murat"
export PLAN_SKU="B1"

# Web App
export APP_NAME="app-waypoint-murat"

# Managed identity for GitHub Actions
export IDENTITY_NAME="id-waypoint-pipeline-murat"

# Display configuration
echo "Azure configuration loaded:"
echo "---------------------------"
echo "Resource Group: $RESOURCE_GROUP"
echo "App Service Plan: $PLAN_NAME"
echo "Plan SKU: $PLAN_SKU"
echo "Web App: $APP_NAME"
echo "Identity: $IDENTITY_NAME"