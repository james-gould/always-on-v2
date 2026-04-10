@description('Naming prefix.')
param resourcePrefix string

@description('Resource tags.')
param tags object

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
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleSetAction: 'Block'
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
          rateLimitThreshold: 1000
          rateLimitDurationInMinutes: 1
          action: 'Block'
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'RegEx'
              matchValue: ['.*']
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

output profileName string = frontDoorProfile.name
output endpoint string = endpoint.properties.hostName
