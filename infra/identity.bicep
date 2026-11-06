@description('Name of the pipeline\'s identity.')
param identityName string

@description('Who may log in as the identity: the start of GitHub\'s subject, from gh api.')
param subjectPrefix string

resource pipelineIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: resourceGroup().location
}

resource githubMainCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2024-11-30' = {
  parent: pipelineIdentity
  name: 'github-main-branch'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: '${subjectPrefix}:ref:refs/heads/main'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// Contributor is a built-in role. Its id is the same in every subscription.
var contributorRoleId = 'b24988ac-6180-42a0-ab88-20f7382dd24c'

resource contributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, pipelineIdentity.id, contributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: pipelineIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output clientId string = pipelineIdentity.properties.clientId
