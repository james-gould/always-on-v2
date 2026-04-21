@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the Private Link Service.')
param plsSubnetId string

@description('Resource ID of the AKS internal load balancer frontend IP configuration.')
param loadBalancerFrontendIpConfigId string

resource pls 'Microsoft.Network/privateLinkServices@2024-05-01' = {
  name: '${resourcePrefix}-pls'
  location: location
  tags: tags
  properties: {
    loadBalancerFrontendIpConfigurations: [
      {
        id: loadBalancerFrontendIpConfigId
      }
    ]
    ipConfigurations: [
      {
        name: 'pls-ip-config'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: plsSubnetId
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    enableProxyProtocol: false
    autoApproval: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
    visibility: {
      subscriptions: [
        subscription().subscriptionId
      ]
    }
  }
}

output privateLinkServiceId string = pls.id
