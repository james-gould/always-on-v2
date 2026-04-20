@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the Cosmos DB private endpoint.')
param cosmosSubnetId string

var accountName = replace('${resourcePrefix}-cosmos', '-', '')

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: true
      }
    ]
    publicNetworkAccess: 'Disabled'
    enableAutomaticFailover: true
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

resource orleansDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' = {
  parent: cosmosAccount
  name: 'alwayson'
  properties: {
    resource: {
      id: 'alwayson'
    }
  }
}

resource clusteringContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: orleansDatabase
  name: 'orleans-clustering'
  properties: {
    resource: {
      id: 'orleans-clustering'
      partitionKey: {
        paths: ['/ClusterId']
        kind: 'Hash'
      }
      defaultTtl: -1
    }
  }
}

resource grainStateContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: orleansDatabase
  name: 'orleans-grain-state'
  properties: {
    resource: {
      id: 'orleans-grain-state'
      partitionKey: {
        paths: ['/PartitionKey']
        kind: 'Hash'
      }
      defaultTtl: -1
    }
  }
}

resource remindersContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-12-01-preview' = {
  parent: orleansDatabase
  name: 'orleans-reminders'
  properties: {
    resource: {
      id: 'orleans-reminders'
      partitionKey: {
        paths: ['/PartitionKey']
        kind: 'Hash'
      }
      defaultTtl: -1
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${resourcePrefix}-cosmos-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: cosmosSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourcePrefix}-cosmos-plsc'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: ['Sql']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'cosmos-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: dnsZone.id
        }
      }
    ]
  }
}

output accountName string = cosmosAccount.name
output accountEndpoint string = cosmosAccount.properties.documentEndpoint
