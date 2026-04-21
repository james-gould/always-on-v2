@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for AKS system node pool.')
param aksSubnetId string

var clusterName = '${resourcePrefix}-aks'
var networkContributorRoleId = '4d97b98b-1d4f-4787-a291-c67834d212e7'

resource aks 'Microsoft.ContainerService/managedClusters@2025-05-01' = {
  name: clusterName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: resourcePrefix
    kubernetesVersion: '1.33'
    enableRBAC: true
    supportPlan: 'KubernetesOfficial'
    nodeResourceGroup: 'MC_${resourceGroup().name}_${clusterName}_${location}'
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'Standard'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        mode: 'System'
        vmSize: 'Standard_D2s_v6'
        osSKU: 'Ubuntu'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        count: 2
        minCount: 2
        maxCount: 5
        enableAutoScaling: true
        maxPods: 110
        enableNodePublicIP: false
        vnetSubnetID: aksSubnetId
      }
    ]
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    autoUpgradeProfile: {
      upgradeChannel: 'stable'
      nodeOSUpgradeChannel: 'NodeImage'
    }
    nodeProvisioningProfile: {
      mode: 'Manual'
    }
  }
}

// AKS cluster identity needs Network Contributor on the subnet to create internal load balancers
resource aksVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: split(aksSubnetId, '/')[8]
}

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: aksVnet
  name: split(aksSubnetId, '/')[10]
}

resource subnetRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksSubnetId, aks.id, networkContributorRoleId)
  scope: aksSubnet
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', networkContributorRoleId)
    principalId: aks.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output clusterName string = aks.name
output clusterIdentityPrincipalId string = aks.identity.principalId
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
