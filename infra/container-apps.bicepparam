using 'main-container-apps.bicep'

var name = 'murat'

param registryName = 'crwaypoint${name}'
param pullIdentityName = 'id-waypoint-${name}'
param environmentName = 'cae-waypoint-${name}'
param containerAppName = 'ca-waypoint-${name}'
param imageTag = readEnvironmentVariable('IMAGE_TAG')
