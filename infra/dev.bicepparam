using 'main.bicep'

// Your name, once. Change 'name' to your own name. The names below are built from it.
var name = 'murat'

param planName = 'asp-waypoint-${name}'
param planSku = 'B1'
param appName = 'app-waypoint-${name}'
param linuxFxVersion = 'NODE|24-lts'
