@description('Region. The same as the resource group, given by main.bicep.')
param location string

@description('Id of the Log Analytics workspace the alert asks.')
param workspaceId string

@description('Name of the action group that gets the alerts.')
@minLength(1)
@maxLength(260)
param actionGroupName string

@description('Where alerts are sent. Read from ALERT_EMAIL, not written in a file.')
@minLength(3)
param alertEmail string

// Who gets the alert. Kept apart from the alert, so more alerts can use it.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'waypoint'
    enabled: true
    emailReceivers: [
      {
        name: 'email'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Runs the query every five minutes, over the last five minutes of logs.
resource highErrorRate 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: 'high-error-rate'
  location: location
  properties: {
    description: 'More than five server errors in five minutes. First, open the workspace logs and read ScStatus and CsUriStem on the AppServiceHTTPLogs rows from the last 15 minutes.'
    severity: 2
    enabled: true
    scopes: [
      workspaceId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: 'AppServiceHTTPLogs | where CsHost !contains ".scm." | where ScStatus >= 500'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 5
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}
