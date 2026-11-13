@description('Region. The same as the resource group, given by main.bicep.')
param location string

@description('Name of the registry. Letters and digits only, unique in all of Azure, and part of its address.')
@minLength(5)
@maxLength(50)
param registryName string

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: registryName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    // No shared admin user and password. Identities get a role instead.
    adminUserEnabled: false
  }
}

output loginServer string = containerRegistry.properties.loginServer
