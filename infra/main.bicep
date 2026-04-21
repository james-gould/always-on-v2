targetScope = 'resourceGroup'

@description('Primary Azure region for all resources.')
param location string = resourceGroup().location

@description('Environment name used for resource naming (e.g. dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Base name prefix for all resources.')
param baseName string = 'alwayson'

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
    location: 'northeurope'
    peLocation: location
    resourcePrefix: resourcePrefix
    tags: tags
    privateEndpointSubnetId: network.outputs.privateEndpointSubnetId
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

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    aksSubnetId: network.outputs.aksSystemSubnetId
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
  }
}

output aksClusterName string = aks.outputs.clusterName
output cosmosAccountName string = cosmosDb.outputs.accountName
output cosmosAccountEndpoint string = cosmosDb.outputs.accountEndpoint
output keyVaultName string = keyVault.outputs.vaultName
output frontDoorEndpoint string = frontDoor.outputs.endpoint
output acrLoginServer string = acr.outputs.loginServer
output siloIdentityClientId string = identity.outputs.identityClientId
