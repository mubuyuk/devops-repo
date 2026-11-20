using 'main.bicep'

// Your name, once. Change 'name' to your own name. The names below are built from it.
var name = 'murat'

param planName = 'asp-waypoint-${name}'
param planSku = 'P0v3'
param appName = 'app-waypoint-${name}'
param linuxFxVersion = 'NODE|24-lts'

param registryName = 'crwaypoint${name}'

param workspaceName = 'log-waypoint-${name}'

param actionGroupName = 'ag-waypoint-${name}'
param alertEmail = readEnvironmentVariable('ALERT_EMAIL')
