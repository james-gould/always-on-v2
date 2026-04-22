@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

var vnetName = '${resourcePrefix}-vnet'

resource aksSystemNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${resourcePrefix}-aks-system-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        // Allow Azure Front Door backend traffic to the public LoadBalancer IP.
        // AFD is the only sanctioned ingress path; all other internet traffic is denied below.
        name: 'AllowFrontDoorInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: ['80', '443', '8080']
        }
      }
      {
        // Allow Azure LB health probes (required for public LoadBalancer services).
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        // Intra-VNet traffic (pod-to-pod, node-to-node, PE access).
        name: 'AllowVnetInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '*'
        }
      }
      {
        // Deny everything else from the internet — no direct-to-IP bypass of AFD.
        name: 'DenyInternetInbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

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
          networkSecurityGroup: {
            id: aksSystemNsg.id
          }
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

resource eventGridDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.eventgrid.azure.net'
  location: 'global'
  tags: tags
}

resource eventGridDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: eventGridDnsZone
  name: '${vnetName}-eg-link'
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
