targetScope = 'resourceGroup'

@description('Primary Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment name used for resource naming (e.g. dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix for all resources.')
param baseName string = 'alwayson'

@description('Azure region for Cosmos DB (may differ from primary location for geo-redundancy).')
param cosmosLocation string = location

@description('Kubernetes version for the AKS cluster.')
param kubernetesVersion string = '1.33'

@description('VM size for AKS system node pool.')
param aksVmSize string = 'Standard_D2s_v6'

@description('Minimum node count for AKS autoscaling.')
@minValue(1)
param aksMinNodeCount int = 2

@description('Maximum node count for AKS autoscaling.')
@minValue(1)
param aksMaxNodeCount int = 5

@description('Maximum autoscale throughput (RU/s) for Cosmos DB.')
param cosmosMaxThroughput int = 1000

@description('Object ID of the Azure AD group or user that should have Key Vault admin access.')
param keyVaultAdminObjectId string

@description('Hostname of the AKS internal ingress (set after K8s ingress is deployed).')
param originHostName string

@description('Resource ID of the AKS internal load balancer frontend IP configuration. Leave empty on first deploy (before k8s services exist).')
param internalLoadBalancerFrontendIpId string = ''

var resourcePrefix = '${baseName}-${environment}'
var tags = {
  project: 'always-on'
  environment: environment
}

// Well-known Azure role definition IDs
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
  }
}

module cosmosDb 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    location: cosmosLocation
    peLocation: location
    resourcePrefix: resourcePrefix
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    maxThroughput: cosmosMaxThroughput
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
    adminObjectId: keyVaultAdminObjectId
  }
}

module redis 'modules/redis.bicep' = {
  name: 'redis'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
  }
}

module eventGrid 'modules/eventgrid.bicep' = {
  name: 'eventgrid'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
  }
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    aksSubnetId: network.outputs.aksSystemSubnetId
    kubernetesVersion: kubernetesVersion
    vmSize: aksVmSize
    minNodeCount: aksMinNodeCount
    maxNodeCount: aksMaxNodeCount
  }
}

module acr 'modules/acr.bicep' = {
  name: 'acr'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    aksKubeletPrincipalId: aks.outputs.kubeletIdentityObjectId
  }
}

var privateLinkServiceId = pls.?outputs.?privateLinkServiceId ?? ''

module frontDoor 'modules/frontdoor.bicep' = {
  name: 'frontdoor'
  params: {
    resourcePrefix: resourcePrefix
    tags: tags
    originHostName: originHostName
    privateLinkServiceId: privateLinkServiceId
    privateLinkLocation: !empty(privateLinkServiceId) ? location : ''
  }
}

module pls 'modules/pls.bicep' = if (!empty(internalLoadBalancerFrontendIpId)) {
  name: 'pls'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    plsSubnetId: network.outputs.plsSubnetId
    loadBalancerFrontendIpConfigId: internalLoadBalancerFrontendIpId
  }
}

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    aksOidcIssuerUrl: aks.outputs.oidcIssuerUrl
    cosmosAccountName: cosmosDb.outputs.accountName
    redisCacheName: redis.outputs.cacheName
    eventGridNamespaceName: eventGrid.outputs.namespaceName
  }
}

// AKS cluster identity needs Network Contributor on the aks-system subnet to create internal load balancers
resource aksSystemSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  name: '${resourcePrefix}-vnet/aks-system'
}

resource aksSubnetRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, 'aks-system-network-contributor')
  scope: aksSystemSubnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: aks.outputs.clusterIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output aksClusterName string = aks.outputs.clusterName
output cosmosAccountName string = cosmosDb.outputs.accountName
output cosmosAccountEndpoint string = cosmosDb.outputs.accountEndpoint
output keyVaultName string = keyVault.outputs.vaultName
output frontDoorEndpoint string = frontDoor.outputs.endpoint
output acrLoginServer string = acr.outputs.loginServer
output siloIdentityClientId string = identity.outputs.identityClientId
output redisHostName string = redis.outputs.hostName
output eventGridEndpoint string = eventGrid.outputs.endpoint
