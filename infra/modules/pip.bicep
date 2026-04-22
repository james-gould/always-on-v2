@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Principal ID of the AKS cluster identity (so the AKS cloud provider can attach this PIP to a LoadBalancer service).')
param aksClusterIdentityPrincipalId string

var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'

resource ingressPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${resourcePrefix}-ingress-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    idleTimeoutInMinutes: 4
  }
}

// AKS cluster identity needs Network Contributor on the PIP to attach it to the LB frontend.
resource pipRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(ingressPip.id, aksClusterIdentityPrincipalId, 'network-contributor')
  scope: ingressPip
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: aksClusterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output pipId string = ingressPip.id
output pipName string = ingressPip.name
output pipAddress string = ingressPip.properties.ipAddress
output pipResourceGroup string = resourceGroup().name
