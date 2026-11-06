param location string
param planName string
param planSku string

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: planName
  location: location
  kind: 'linux'
  sku: {
    name: planSku
  }
  properties: {
    reserved: true
  }
}

// Another file cannot read this resource directly. What it needs comes out through an output.
output appServicePlanId string = appServicePlan.id
