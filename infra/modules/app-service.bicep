param location string
param appName string
param appServicePlanId string
param linuxFxVersion string

@description('Id of the Log Analytics workspace that gets the logs.')
param workspaceId string

resource appService 'Microsoft.Web/sites@2025-03-01' = {
  name: appName
  location: location
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

// Sends the app's logs to the workspace. Without it, nothing ends up there.
resource appServiceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-workspace'
  scope: appService
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
    ]
  }
}

output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
