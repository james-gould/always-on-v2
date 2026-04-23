@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Log Analytics retention in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

// ───────────────────────────────────────────────────────────
// Log Analytics workspace — Container Insights logs + stdout/stderr
// ───────────────────────────────────────────────────────────
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${resourcePrefix}-law'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// ───────────────────────────────────────────────────────────
// Azure Monitor workspace — Managed Prometheus metric store
// ───────────────────────────────────────────────────────────
resource azureMonitorWorkspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: '${resourcePrefix}-amw'
  location: location
  tags: tags
  properties: {}
}

// ───────────────────────────────────────────────────────────
// Data Collection Endpoint + Rule for Prometheus scrape → AMW
// The AKS Managed Prometheus addon picks up the DCR via an association
// (created alongside the cluster in main.bicep).
// ───────────────────────────────────────────────────────────
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: '${resourcePrefix}-dce'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource prometheusDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${resourcePrefix}-prom-dcr'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: ['Microsoft-PrometheusMetrics']
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccount1'
          accountResourceId: azureMonitorWorkspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-PrometheusMetrics']
        destinations: ['MonitoringAccount1']
      }
    ]
  }
}

// ───────────────────────────────────────────────────────────
// Data Collection Rule for Container Insights → LAW
// ───────────────────────────────────────────────────────────
resource containerInsightsDcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${resourcePrefix}-ci-dcr'
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    dataSources: {
      extensions: [
        {
          name: 'ContainerInsightsExtension'
          extensionName: 'ContainerInsights'
          streams: ['Microsoft-ContainerInsights-Group-Default']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalytics.id
          name: 'ciworkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-ContainerInsights-Group-Default']
        destinations: ['ciworkspace']
      }
    ]
    description: 'Container Insights DCR for AKS'
  }
}

output logAnalyticsWorkspaceId string = logAnalytics.id
output logAnalyticsWorkspaceName string = logAnalytics.name
output azureMonitorWorkspaceId string = azureMonitorWorkspace.id
output azureMonitorWorkspaceName string = azureMonitorWorkspace.name
output prometheusDcrId string = prometheusDcr.id
output containerInsightsDcrId string = containerInsightsDcr.id
