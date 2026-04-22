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

@description('Service Bus namespace name for AAD data-plane RBAC assignment.')
param serviceBusNamespaceName string

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

// Azure Service Bus Data Owner role: allows Send, Receive and management of
// queues used by the reservation flow. Role definition ID is well-known.
var serviceBusDataOwnerRoleId = '090c5cfd-751d-490a-894a-3ce6f1109419'

resource serviceBus 'Microsoft.ServiceBus/namespaces@2024-01-01' existing = {
  name: serviceBusNamespaceName
}

resource serviceBusRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: serviceBus
  name: guid(managedIdentity.id, serviceBus.id, serviceBusDataOwnerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', serviceBusDataOwnerRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output identityName string = managedIdentity.name
output identityClientId string = managedIdentity.properties.clientId
output identityPrincipalId string = managedIdentity.properties.principalId
