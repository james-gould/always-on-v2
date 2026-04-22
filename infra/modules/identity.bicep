@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('OIDC issuer URL from the AKS cluster.')
param aksOidcIssuerUrl string

@description('Kubernetes namespace for the workload.')
param k8sNamespace string = 'default'

@description('Kubernetes service account name for the workload.')
param k8sServiceAccountName string = 'silo-sa'

@description('Cosmos DB account name for RBAC role assignment.')
param cosmosAccountName string

@description('Redis cache name for AAD data-plane access policy assignment.')
param redisCacheName string

@description('Event Grid namespace name for AAD data-plane RBAC assignment.')
param eventGridNamespaceName string

var identityName = '${resourcePrefix}-silo-id'

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
  tags: tags
}

resource federatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: managedIdentity
  name: '${resourcePrefix}-silo-fic'
  properties: {
    issuer: aksOidcIssuerUrl
    subject: 'system:serviceaccount:${k8sNamespace}:${k8sServiceAccountName}'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosAccountName
}

// Cosmos DB Built-in Data Contributor = 00000000-0000-0000-0000-000000000002
resource cosmosRbac 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmosAccount
  name: guid(managedIdentity.id, cosmosAccount.id, '00000000-0000-0000-0000-000000000002')
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    principalId: managedIdentity.properties.principalId
    scope: cosmosAccount.id
  }
}

// Azure Cache for Redis access-policy assignment (AAD data-plane).
// "Data Contributor" is the built-in policy allowing read/write of keys without
// cluster admin rights.
resource redisCache 'Microsoft.Cache/redis@2024-11-01' existing = {
  name: redisCacheName
}

resource redisAccessPolicy 'Microsoft.Cache/redis/accessPolicyAssignments@2024-11-01' = {
  parent: redisCache
  name: guid(managedIdentity.id, redisCache.id, 'Data Contributor')
  properties: {
    accessPolicyName: 'Data Contributor'
    objectId: managedIdentity.properties.principalId
    objectIdAlias: managedIdentity.name
  }
}

// Event Grid Data Sender + Data Receiver roles: allow publishing to namespace
// topics and consuming via pull delivery. Role definition IDs are well-known.
var eventGridDataSenderRoleId = 'd5a91429-5739-47e2-a06b-3470a27159e7'
var eventGridDataReceiverRoleId = '78cbd9e7-9798-4e2e-9b5a-547d9ebb31fb'

resource eventGridNamespace 'Microsoft.EventGrid/namespaces@2024-06-01-preview' existing = {
  name: eventGridNamespaceName
}

resource eventGridSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventGridNamespace
  name: guid(managedIdentity.id, eventGridNamespace.id, eventGridDataSenderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventGridDataSenderRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource eventGridReceiverRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: eventGridNamespace
  name: guid(managedIdentity.id, eventGridNamespace.id, eventGridDataReceiverRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', eventGridDataReceiverRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output identityName string = managedIdentity.name
output identityClientId string = managedIdentity.properties.clientId
output identityPrincipalId string = managedIdentity.properties.principalId
