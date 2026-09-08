targetScope = 'subscription'

@description('Deployment region, for example japaneast.')
param location string = 'japaneast'

@allowed([
  'dev'
  'test'
])
param environment string = 'dev'

@minLength(2)
@maxLength(20)
param projectName string = 'portfolio'

@description('Non-sensitive owner identifier used as a tag.')
@minLength(2)
param owner string

@description('SSH public key. Never provide a private key.')
@secure()
param sshPublicKey string

@description('Single trusted public IPv4 CIDR such as 203.0.113.10/32. 0.0.0.0/0 is rejected by scripts.')
param adminCidr string

@description('Open HTTP for a short learning test. Keep false by default.')
param openHttp bool = false

param vmSize string = 'Standard_B1s'
param adminUsername string = 'azureadmin'

@description('CPUアラート・OSログ関連アラートの通知先メールアドレス(運用担当者)')
param alertEmailAddress string

var regionCode = location == 'japaneast' ? 'jpe' : take(replace(location, ' ', ''), 3)
var suffix = '${projectName}-${environment}-${regionCode}-001'
var resourceGroupName = 'rg-${suffix}'
var commonTags = {
  Environment: environment
  Project: projectName
  Owner: owner
  ManagedBy: 'Bicep'
  DataClassification: 'Public-Demo'
}

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

module workload 'modules/workload.bicep' = {
  name: 'workload-${environment}'
  scope: resourceGroup
  params: {
    location: location
    suffix: suffix
    commonTags: commonTags
    sshPublicKey: sshPublicKey
    adminCidr: adminCidr
    openHttp: openHttp
    vmSize: vmSize
    adminUsername: adminUsername
    alertEmailAddress: alertEmailAddress
  }
}

module backup 'modules/backup.bicep' = {
  name: 'backup-${environment}'
  scope: resourceGroup
  params: {
    location: location
    suffix: suffix
    commonTags: commonTags
    vmName: workload.outputs.vmName
    vmId: workload.outputs.vmId
  }
}

output resourceGroupName string = resourceGroup.name
output vmName string = workload.outputs.vmName
output publicIpAddress string = workload.outputs.publicIpAddress
output sshCommand string = 'ssh ${adminUsername}@${workload.outputs.publicIpAddress}'
output recoveryVaultName string = backup.outputs.recoveryVaultName
