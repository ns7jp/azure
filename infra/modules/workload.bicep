param location string
param suffix string
param commonTags object
@secure()
param sshPublicKey string
param adminCidr string
param openHttp bool
param vmSize string
param adminUsername string
@description('CPUアラート・OSログ関連アラートの通知先メールアドレス')
param alertEmailAddress string

var vnetName = 'vnet-${suffix}'
var subnetName = 'snet-server-${suffix}'
var nsgName = 'nsg-${suffix}'
var pipName = 'pip-${suffix}'
var nicName = 'nic-${suffix}'
var vmName = 'vm-${suffix}'
var lawName = 'log-${suffix}'
var alertName = 'alert-cpu-${suffix}'
var actionGroupName = 'ag-${suffix}'
var dcrName = 'dcr-${suffix}'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  tags: commonTags
  properties: {
    securityRules: concat([
      {
        name: 'Allow-SSH-From-Admin'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: adminCidr
          destinationAddressPrefix: '*'
        }
      }
    ], openHttp ? [
      {
        name: 'Allow-HTTP-For-Lab'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: '*'
        }
      }
    ] : [])
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: '10.20.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: pipName
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: nicName
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnetName)
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: lawName
  location: location
  tags: commonTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  tags: commonTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: 30
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: base64(loadTextContent('../cloud-init.yaml'))
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// -----------------------------------------------------------------------------
// OSログ収集(Azure Monitor Agent + Data Collection Rule)
// VM内のCPU/ディスク空き容量のパフォーマンスカウンターと、認証・エラー系のsyslogを
// Log Analyticsへ送信する。09-gap-analysis-and-roadmap.mdで「高」とされていた
// 「監視通知とOSログ収集」の未構成状態を解消する。
// -----------------------------------------------------------------------------
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: commonTags
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perfCounterDataSource'
          streams: [
            'Microsoft-Perf'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\LogicalDisk(_Total)\\% Free Space'
          ]
        }
      ]
      syslog: [
        {
          name: 'sysLogsDataSource'
          streams: [
            'Microsoft-Syslog'
          ]
          facilityNames: [
            'auth'
            'authpriv'
            'daemon'
            'syslog'
          ]
          logLevels: [
            'Warning'
            'Error'
            'Critical'
            'Alert'
            'Emergency'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspace.id
          name: 'laDestination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-Perf'
        ]
        destinations: [
          'laDestination'
        ]
      }
      {
        streams: [
          'Microsoft-Syslog'
        ]
        destinations: [
          'laDestination'
        ]
      }
    ]
  }
}

resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  name: 'AzureMonitorLinuxAgent'
  parent: vm
  location: location
  tags: commonTags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.33'
    autoUpgradeMinorVersion: true
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcra-${suffix}'
  scope: vm
  properties: {
    dataCollectionRuleId: dcr.id
  }
  dependsOn: [
    amaExtension
  ]
}

// -----------------------------------------------------------------------------
// Action Group: CPUアラートの通知先(メール)
// -----------------------------------------------------------------------------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: commonTags
  properties: {
    groupShortName: take(replace(suffix, '-', ''), 12)
    enabled: true
    emailReceivers: [
      {
        name: 'ops-email'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

resource cpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertName
  location: 'global'
  tags: commonTags
  properties: {
    description: 'Average VM CPU is over 80 percent for five minutes.'
    severity: 2
    enabled: true
    scopes: [
      vm.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpu'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output vmName string = vm.name
output workspaceName string = workspace.name
output publicIpAddress string = publicIp.properties.ipAddress
output actionGroupName string = actionGroup.name
