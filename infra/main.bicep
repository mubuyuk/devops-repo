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

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'app-service-plan'
  params: {
    location: location
    planName: planName
    planSku: planSku
  }
}

module appService 'modules/app-service.bicep' = {
  name: 'app-service'
  params: {
    location: location
    appName: appName
    appServicePlanId: appServicePlan.outputs.appServicePlanId
    linuxFxVersion: linuxFxVersion
  }
}

output appServiceUrl string = appService.outputs.appServiceUrl
