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

module observability 'modules/observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
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
    logAnalyticsWorkspaceId: observability.outputs.logAnalyticsWorkspaceId
  }
}

// Attach the Prometheus Data Collection Rule to the AKS cluster. The managed
// Prometheus addon (enabled above) uses this association to route scraped
// metrics into the Azure Monitor workspace.
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-05-01' existing = {
  name: '${resourcePrefix}-aks'
}

resource prometheusDcra 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${resourcePrefix}-prom-dcra'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: observability.outputs.prometheusDcrId
    description: 'Prometheus metrics scrape from AKS to Azure Monitor workspace.'
  }
  dependsOn: [
    aks
  ]
}

resource containerInsightsDcra 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: '${resourcePrefix}-ci-dcra'
  scope: aksCluster
  properties: {
    dataCollectionRuleId: observability.outputs.containerInsightsDcrId
    description: 'Container Insights logs from AKS to Log Analytics workspace.'
  }
  dependsOn: [
    aks
  ]
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

module ingressPip 'modules/pip.bicep' = {
  name: 'ingress-pip'
  params: {
    location: location
    resourcePrefix: resourcePrefix
    tags: tags
    aksClusterIdentityPrincipalId: aks.outputs.clusterIdentityPrincipalId
  }
}

module frontDoor 'modules/frontdoor.bicep' = {
  name: 'frontdoor'
  params: {
    resourcePrefix: resourcePrefix
    tags: tags
    originHostName: ingressPip.outputs.pipAddress
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

output aksClusterName string = aks.outputs.clusterName
output cosmosAccountName string = cosmosDb.outputs.accountName
output cosmosAccountEndpoint string = cosmosDb.outputs.accountEndpoint
output keyVaultName string = keyVault.outputs.vaultName
output frontDoorEndpoint string = frontDoor.outputs.endpoint
output acrLoginServer string = acr.outputs.loginServer
output siloIdentityClientId string = identity.outputs.identityClientId
output redisHostName string = redis.outputs.hostName
output eventGridEndpoint string = eventGrid.outputs.endpoint
output ingressPipName string = ingressPip.outputs.pipName
output ingressPipAddress string = ingressPip.outputs.pipAddress
output ingressPipResourceGroup string = ingressPip.outputs.pipResourceGroup
output logAnalyticsWorkspaceName string = observability.outputs.logAnalyticsWorkspaceName
output azureMonitorWorkspaceName string = observability.outputs.azureMonitorWorkspaceName
