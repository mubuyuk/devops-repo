@description('Region.')
param location string

@description('Name of the identity the container app uses to pull images.')
param identityName string

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: identityName
  location: location
}

// The full resource id. The container app needs it to use the identity.
output pullIdentityId string = pullIdentity.id

// The id roles are given to. We need it for AcrPull.
output pullIdentityPrincipalId string = pullIdentity.properties.principalId
