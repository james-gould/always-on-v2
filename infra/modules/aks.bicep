@description('Azure region.')
param location string

@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Subnet resource ID for AKS system node pool.')
param aksSubnetId string

@description('Kubernetes version.')
param kubernetesVersion string = '1.33'

@description('VM size for the system node pool.')
param vmSize string = 'Standard_D2s_v6'

@description('Minimum node count for autoscaling.')
@minValue(1)
param minNodeCount int = 2

@description('Maximum node count for autoscaling.')
@minValue(1)
param maxNodeCount int = 5

@description('Resource ID of the Log Analytics workspace for Container Insights.')
param logAnalyticsWorkspaceId string

var clusterName = '${resourcePrefix}-aks'

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
    kubernetesVersion: kubernetesVersion
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
        vmSize: vmSize
        osSKU: 'Ubuntu'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        count: minNodeCount
        minCount: minNodeCount
        maxCount: maxNodeCount
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
    // Container Insights — ships stdout/stderr + kube events to Log Analytics.
    addonProfiles: {
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
          useAADAuth: 'true'
        }
      }
    }
    // Azure Managed Prometheus — node/pod/kube-state metrics to Azure Monitor workspace.
    // The DCR association (created in main.bicep) tells the cluster where to send them.
    azureMonitorProfile: {
      metrics: {
        enabled: true
        kubeStateMetrics: {
          metricLabelsAllowlist: ''
          metricAnnotationsAllowList: ''
        }
      }
    }
  }
}

output clusterName string = aks.name
output clusterId string = aks.id
output clusterIdentityPrincipalId string = aks.identity.principalId
output kubeletIdentityObjectId string = aks.properties.identityProfile.kubeletidentity.objectId
output oidcIssuerUrl string = aks.properties.oidcIssuerProfile.issuerURL
