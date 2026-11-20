@description('Region. The same as the resource group, unless you give another.')
param location string = resourceGroup().location

@description('Name of the App Service plan.')
param planName string

@description('Plan tier: B1, or P0v3 for the faster alternative.')
param planSku string = 'B1'

@description('Name of the web app. Part of its address, so it must be unique in all of Azure.')
param appName string

@description('Language and version, for example NODE|24-lts.')
param linuxFxVersion string

@description('Name of the container registry. Letters and digits only, unique in all of Azure.')
param registryName string

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Name of the action group that gets the alerts.')
param actionGroupName string

@description('Where alerts are sent.')
param alertEmail string

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'app-service-plan'
  params: {
    location: location
    planName: planName
    planSku: planSku
  }
}

module containerRegistry 'modules/container-registry.bicep' = {
  name: 'container-registry'
  params: {
    location: location
    registryName: registryName
  }
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    location: location
    workspaceName: workspaceName
  }
}

module appService 'modules/app-service.bicep' = {
  name: 'app-service'
  params: {
    location: location
    appName: appName
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    linuxFxVersion: linuxFxVersion
    workspaceId: logAnalytics.outputs.workspaceId
  }
}

module alerts 'modules/alerts.bicep' = {
  name: 'alerts'
  params: {
    location: location
    workspaceId: logAnalytics.outputs.workspaceId
    actionGroupName: actionGroupName
    alertEmail: alertEmail
  }
}

output appServiceUrl string = appService.outputs.appServiceUrl
output registryLoginServer string = containerRegistry.outputs.loginServer
