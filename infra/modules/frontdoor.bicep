@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

@description('Hostname (or public IP) of the AKS ingress load balancer.')
param originHostName string

@description('HTTP port of the origin.')
param originHttpPort int = 8080

var profileName = '${resourcePrefix}-afd'

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {}
}

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  parent: frontDoorProfile
  name: '${resourcePrefix}-endpoint'
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: replace('${resourcePrefix}-waf', '-', '')
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Log'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleSetAction: 'Log'
        }
      ]
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitRule'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitThreshold: 600000
          rateLimitDurationInMinutes: 1
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'RegEx'
              matchValue: ['.+']
            }
          ]
        }
      ]
    }
  }
}

resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = {
  parent: frontDoorProfile
  name: '${resourcePrefix}-security'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Origin group, origin, and route — routes Front Door traffic to AKS internally
// ---------------------------------------------------------------------------

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  parent: frontDoorProfile
  name: 'aks-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/alive'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 30
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  parent: originGroup
  name: 'aks-origin'
  properties: {
    hostName: originHostName
    httpPort: originHttpPort
    httpsPort: 443
    originHostHeader: originHostName
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: false
  }
}

resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  parent: endpoint
  name: 'default-route'
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

output profileName string = frontDoorProfile.name
output endpoint string = endpoint.properties.hostName
output frontDoorId string = frontDoorProfile.properties.frontDoorId
