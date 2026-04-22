@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the private endpoint.')
param privateEndpointSubnetId string

@description('Name of the namespace topic for reservations.')
param topicName string = 'reservations'

@description('Name of the queue event subscription.')
param subscriptionName string = 'reservations-ready'

var namespaceName = '${resourcePrefix}-eventgrid'

resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2024-06-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    capacity: 1
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    isZoneRedundant: false
  }
}

resource topic 'Microsoft.EventGrid/namespaces/topics@2024-06-01-preview' = {
  parent: eventGridNamespace
  name: topicName
  properties: {
    publisherType: 'Custom'
    inputSchema: 'CloudEventSchemaV1_0'
    eventRetentionInDays: 1
  }
}

resource subscription 'Microsoft.EventGrid/namespaces/topics/eventSubscriptions@2024-06-01-preview' = {
  parent: topic
  name: subscriptionName
  properties: {
    deliveryConfiguration: {
      deliveryMode: 'Queue'
      queue: {
        receiveLockDurationInSeconds: 30
        maxDeliveryCount: 10
        eventTimeToLive: 'PT10M'
      }
    }
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${resourcePrefix}-eventgrid-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourcePrefix}-eventgrid-plsc'
        properties: {
          privateLinkServiceId: eventGridNamespace.id
          groupIds: ['topic']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.eventgrid.azure.net'
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'eventgrid-dns-group'
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

output namespaceName string = eventGridNamespace.name
output namespaceId string = eventGridNamespace.id
// Event Grid Namespace endpoint: <name>.<region>-1.eventgrid.azure.net
output endpoint string = 'https://${namespaceName}.${location}-1.eventgrid.azure.net'
output topicName string = topic.name
output subscriptionName string = subscription.name
