@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet ID for the AKS system node pool.')
param systemSubnetId string

@description('Subnet ID for the Gateway node pool.')
param gatewaySubnetId string

@description('Subnet ID for the Silo node pool.')
param siloSubnetId string

var clusterName = '${resourcePrefix}-aks'

resource aks 'Microsoft.ContainerService/managedClusters@2024-09-02-preview' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: resourcePrefix
    kubernetesVersion: '1.31'
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'cilium'
      networkDataplane: 'cilium'
      serviceCidr: '172.16.0.0/16'
      dnsServiceIP: '172.16.0.10'
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        vmSize: 'Standard_D2s_v5'
        count: 2
        minCount: 2
        maxCount: 4
        enableAutoScaling: true
        availabilityZones: ['1', '2', '3']
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: systemSubnetId
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
      }
      {
        name: 'gateway'
        mode: 'User'
        vmSize: 'Standard_D4s_v5'
        count: 2
        minCount: 2
        maxCount: 20
        enableAutoScaling: true
        availabilityZones: ['1', '2', '3']
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: gatewaySubnetId
        nodeLabels: {
          workload: 'gateway'
        }
      }
      {
        name: 'silo'
        mode: 'User'
        vmSize: 'Standard_E4s_v5'
        count: 3
        minCount: 3
        maxCount: 15
        enableAutoScaling: true
        availabilityZones: ['1', '2', '3']
        osType: 'Linux'
        osSKU: 'AzureLinux'
        vnetSubnetID: siloSubnetId
        nodeLabels: {
          workload: 'silo'
        }
      }
    ]
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalytics.id
        }
      }
    }
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
    }
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${resourcePrefix}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output clusterName string = aks.name
output clusterIdentityPrincipalId string = aks.identity.principalId
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
