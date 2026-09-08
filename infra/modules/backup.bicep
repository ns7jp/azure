// =============================================================================
// modules/backup.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// Recovery Services Vault(rsv-<suffix>)と日次バックアップポリシー
// (bkp-<suffix>)を作成し、単一VMをバックアップ保護対象として登録する。
//
// README/03-basic-design.mdで仮置きしていたRPO 24時間を、実際にバックアップを
// 取得することで満たせるようにする。採用理由は
// docs/decisions/ADR-004-backup-policy.md を参照。
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string

@description('リソース名の共通サフィックス(main.bicepのsuffixと同じ値)')
param suffix string

param commonTags object

@description('バックアップ対象VMの名前(workload.bicepの出力を渡す)')
param vmName string

@description('バックアップ対象VMのリソースID(workload.bicepの出力を渡す)')
param vmId string

var vaultName = 'rsv-${suffix}'
var policyName = 'bkp-${suffix}'
var currentResourceGroupName = resourceGroup().name

// -----------------------------------------------------------------------------
// Recovery Services Vault本体
// -----------------------------------------------------------------------------
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: vaultName
  location: location
  tags: commonTags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    // バックアップジョブが失敗した場合にAzure Monitor経由で通知する(組み込み機能)。
    // 基礎編では専用のAction Group連携までは行わず、Azure Portalの通知設定に委ねる。
    monitoringSettings: {
      azureMonitorAlertSettings: {
        alertsForAllJobFailures: 'Enabled'
      }
    }
  }
}

// -----------------------------------------------------------------------------
// バックアップストレージの冗長性設定:LRS(ローカル冗長ストレージ)
// README「コスト配慮」の方針に基づき、学習用途では既定のGRS(Geo冗長)ではなく
// 最小コストのLRSを採用する。本番相当のリージョン障害耐性が必要になった場合は
// GRSへの変更を検討する(ADR-004「見直し条件」を参照)。
// -----------------------------------------------------------------------------
resource vaultStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-04-01' = {
  parent: recoveryVault
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: 'LocallyRedundant'
    crossRegionRestoreFlag: false
  }
}

// -----------------------------------------------------------------------------
// バックアップポリシー:bkp-<suffix>
// 毎日02:00(Tokyo Standard Time)にVM全体(IaasVMバックアップ)を取得し、30日間保持する。
// 週次・月次の長期保持は基礎編の学習範囲を超えるため対象外とする(発展編の
// infra/advanced/modules/backup.bicep を参照)。
// -----------------------------------------------------------------------------
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryVault
  name: policyName
  properties: {
    backupManagementType: 'AzureIaasVM'
    timeZone: 'Tokyo Standard Time'
    instantRPDetails: {}
    instantRpRetentionRangeInDays: 2
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2024-01-01T02:00:00Z' // 日付部分は無視され、時刻(02:00)のみが有効
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// バックアップ保護対象の登録
// コンテナ名・保護アイテム名を
// "iaasvmcontainer;iaasvmcontainerv2;<リソースグループ名>;<VM名>" の形式で
// 組み立てることで、コンテナ登録を暗黙的に行う。
// -----------------------------------------------------------------------------
resource protectedItem 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = {
  name: '${recoveryVault.name}/Azure/iaasvmcontainer;iaasvmcontainerv2;${currentResourceGroupName};${vmName}/vm;iaasvmcontainerv2;${currentResourceGroupName};${vmName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: backupPolicy.id
    sourceResourceId: vmId
  }
}

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】
// ・初回バックアップジョブの完了確認(数時間かかることがある)
// ・隔離環境(別名VM等)への復元試験(試験ID BK-02、docs/06-test-plan.md参照)
// ・復元手順は docs/07-operations-runbook.md の「バックアップ・復元」を参照
// -----------------------------------------------------------------------------

output recoveryVaultId string = recoveryVault.id
output recoveryVaultName string = recoveryVault.name
output backupPolicyName string = backupPolicy.name
