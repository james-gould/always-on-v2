targetScope = 'subscription'

param resourceGroupName string

param location string

param principalId string

resource rg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: resourceGroupName
  location: location
}

module cosmosdb 'cosmosdb/cosmosdb.bicep' = {
  name: 'cosmosdb'
  scope: rg
  params: {
    location: location
  }
}

module cosmosdb_roles 'cosmosdb-roles/cosmosdb-roles.bicep' = {
  name: 'cosmosdb-roles'
  scope: rg
  params: {
    location: location
    cosmosdb_outputs_name: cosmosdb.outputs.name
    principalId: principalId
  }
}