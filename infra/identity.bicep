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

module contributorRole 'modules/contributor-role.bicep' = {
  name: 'contributor-role'
  params: {
    principalId: pipelineIdentity.properties.principalId
  }
}

output clientId string = pipelineIdentity.properties.clientId
