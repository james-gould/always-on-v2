@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the private endpoint.')
param privateEndpointSubnetId string

@description('Capacity of the Basic/Standard SKU (C family). Use 1 for small dev, higher for prod.')
@minValue(0)
param capacity int = 1

@description('Redis SKU family. C = Basic/Standard, P = Premium. Premium is required for VNet injection but Private Endpoint is supported on Standard.')
@allowed(['C', 'P'])
param family string = 'C'

@description('Redis SKU name.')
@allowed(['Basic', 'Standard', 'Premium'])
param skuName string = 'Standard'

var cacheName = '${resourcePrefix}-redis'

resource redis 'Microsoft.Cache/redis@2024-11-01' = {
  name: cacheName
  location: location
  tags: tags
  properties: {
    sku: {
      name: skuName
      family: family
      capacity: capacity
    }
    // AAD-only: Silo authenticates with its workload identity, no keys in Key Vault.
    disableAccessKeyAuthentication: true
    publicNetworkAccess: 'Disabled'
    redisConfiguration: {
      'aad-enabled': 'true'
    }
    minimumTlsVersion: '1.2'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${resourcePrefix}-redis-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourcePrefix}-redis-plsc'
        properties: {
          privateLinkServiceId: redis.id
          groupIds: ['redisCache']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.redis.cache.windows.net'
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'redis-dns-group'
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

output cacheName string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
