@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the private endpoint.')
param privateEndpointSubnetId string

@description('Name of the reservations queue.')
param reservationsQueueName string = 'reservations-ready'

// Premium SKU is required for VNet integration / Private Link support.
var namespaceName = '${resourcePrefix}-sb'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2024-01-01' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Premium'
    tier: 'Premium'
    capacity: 1
  }
  properties: {
    // AAD-only: the silo authenticates with its workload identity; no SAS.
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: '1.2'
    zoneRedundant: false
  }
}

resource reservationsQueue 'Microsoft.ServiceBus/namespaces/queues@2024-01-01' = {
  parent: serviceBus
  name: reservationsQueueName
  properties: {
    lockDuration: 'PT30S'
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    defaultMessageTimeToLive: 'PT10M'
    requiresDuplicateDetection: false
    requiresSession: false
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${resourcePrefix}-sb-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourcePrefix}-sb-plsc'
        properties: {
          privateLinkServiceId: serviceBus.id
          groupIds: ['namespace']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.servicebus.windows.net'
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'sb-dns-group'
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

output namespaceName string = serviceBus.name
output namespaceId string = serviceBus.id
output endpoint string = 'https://${serviceBus.name}.servicebus.windows.net'
output reservationsQueueName string = reservationsQueue.name
