@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for the Key Vault private endpoint.')
param keyVaultSubnetId string

@description('Object ID of the principal granted Key Vault Administrator role.')
param adminObjectId string

var vaultName = replace('${resourcePrefix}-kv', '-', '')

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Key Vault Administrator role
resource adminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, adminObjectId, '00482a5a-887f-4fb3-b363-3b7fe8e74483')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483')
    principalId: adminObjectId
    principalType: 'User'
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${resourcePrefix}-kv-pe'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: keyVaultSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourcePrefix}-kv-plsc'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'keyvault-dns-group'
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

output vaultName string = keyVault.name
output vaultUri string = keyVault.properties.vaultUri
