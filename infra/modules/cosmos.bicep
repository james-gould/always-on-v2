@description('Azure region.')
param location string

@description('Azure region for the private endpoint (must match the VNet).')
param peLocation string = location

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for private endpoints.')
param privateEndpointSubnetId string

var accountName = replace('${resourcePrefix}-cosmos', '-', '')

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: accountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: false
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    publicNetworkAccess: 'Disabled'
    enableAutomaticFailover: true
  }
}

resource orleansDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-12-01-preview' = {
  parent: cosmosAccount
  name: 'alwayson'
  properties: {
    resource: {
      id: 'alwayson'
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 1000
      }
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
  location: peLocation
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
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
