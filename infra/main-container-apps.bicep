@description('Region. The same as the resource group, unless you give another.')
param location string = resourceGroup().location

@description('Name of the container registry. Letters and digits only, unique in all of Azure.')
param registryName string

@description('Name of the identity the container app uses to pull images.')
param pullIdentityName string

@description('Name of the Container Apps environment.')
param environmentName string

@description('Name of the container app. At most 32 characters.')
param containerAppName string

@description('Which image to run. The short commit id.')
param imageTag string

@description('Region for Container Apps. The same as the rest, unless you give another.')
param containerAppsLocation string = location

// 1. The registry, where the images are
module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    location: location
    registryName: registryName
  }
}

// 2. The identity the app pulls images with
module pullIdentity 'modules/pull-identity.bicep' = {
  name: 'pull-identity'
  params: {
    location: location
    identityName: pullIdentityName
  }
}

// 3. The environment and the app
module containerApp 'modules/container-app.bicep' = {
  name: 'container-app'
  params: {
    location: containerAppsLocation
    environmentName: environmentName
    containerAppName: containerAppName
    registryLoginServer: containerRegistry.outputs.loginServer
    pullIdentityId: pullIdentity.outputs.pullIdentityId
    imageTag: imageTag
  }
}

output registryLoginServer string = containerRegistry.outputs.loginServer
output pullIdentityId string = pullIdentity.outputs.pullIdentityId
output pullIdentityPrincipalId string = pullIdentity.outputs.pullIdentityPrincipalId
output containerAppUrl string = containerApp.outputs.containerAppUrl
