@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

var vnetName = '${resourcePrefix}-vnet'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/14'
      ]
    }
    subnets: [
      {
        name: 'aks-system'
        properties: {
          addressPrefix: '10.0.0.0/16'
        }
      }
      {
        name: 'aks-gateway'
        properties: {
          addressPrefix: '10.1.0.0/16'
        }
      }
      {
        name: 'aks-silo'
        properties: {
          addressPrefix: '10.2.0.0/16'
        }
      }
      {
        // Shared subnet for all private endpoints (Cosmos, Key Vault, etc.)
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.3.0.0/24'
        }
      }
      {
        // Subnet for Private Link Service (Front Door → AKS internal LB)
        name: 'private-link-service'
        properties: {
          addressPrefix: '10.3.1.0/24'
          privateLinkServiceNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource cosmosDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.documents.azure.com'
  location: 'global'
  tags: tags
}

resource cosmosDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: cosmosDnsZone
  name: '${vnetName}-cosmos-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource keyVaultDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  tags: tags
}

resource keyVaultDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: keyVaultDnsZone
  name: '${vnetName}-keyvault-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource redisDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.redis.cache.windows.net'
  location: 'global'
  tags: tags
}

resource redisDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: redisDnsZone
  name: '${vnetName}-redis-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

output vnetId string = vnet.id
output aksSystemSubnetId string = '${vnet.id}/subnets/aks-system'
output aksGatewaySubnetId string = '${vnet.id}/subnets/aks-gateway'
output aksSiloSubnetId string = '${vnet.id}/subnets/aks-silo'
output privateEndpointSubnetId string = '${vnet.id}/subnets/private-endpoints'
output plsSubnetId string = '${vnet.id}/subnets/private-link-service'
