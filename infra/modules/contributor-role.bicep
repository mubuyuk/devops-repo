@description('The identity that gets the role.')
param principalId string

// Contributor is built in. Its id is the same everywhere.
var roleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var roleType = 'Microsoft.Authorization/roleDefinitions'

resource role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId(roleType, roleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
