// =============================================================================
// modules/backup.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// Recovery Services Vault(rsv-sanrise-prod-jpe)と、日次/週次/月次のバックアップ
// ポリシー(bkp-sanrise-standard-daily)を作成し、5台のVMをバックアップ保護対象
// として登録する。
//
// これにより、磁気テープによる手動バックアップ運用から、Azure上での
// 自動バックアップ体制(RPO/RTO要件を満たす)へ移行する。
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string = 'japaneast'

@description('バックアップ対象VMの名前一覧(compute.bicepの出力を渡す)')
param vmNames array

@description('バックアップ対象VMのリソースID一覧(compute.bicepの出力を渡す。vmNamesと同じ並び順であること)')
param vmIds array

// バックアップ保護対象の登録時にコンテナ名・保護アイテム名を組み立てるため、
// デプロイ先のリソースグループ名を取得する
var currentResourceGroupName = resourceGroup().name

// -----------------------------------------------------------------------------
// Recovery Services Vault本体
// -----------------------------------------------------------------------------
resource recoveryVault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: 'rsv-sanrise-prod-jpe'
  location: location
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    // 学習用途のコスト重視構成のため、リージョン間フェイルオーバー(ASR)は導入しない。
    // バックアップデータの地理的保全はGRS(Geo冗長ストレージ)のみで確保する。
    publicNetworkAccess: 'Enabled'
    // Azure Monitorへのバックアップジョブ失敗通知を有効化する(組み込みのバックアップアラート機能)。
    // これにより alert-backup-job-failure 相当の通知を補完する。
    // 補足:このプロパティのスキーマはAPIバージョンにより変更される可能性があるため、
    // az bicep build / what-if で必ず事前検証すること。
    monitoringSettings: {
      azureBackupSettings: {
        alertsForAllJobFailures: 'Enabled'
      }
    }
  }
}

// -----------------------------------------------------------------------------
// バックアップストレージの冗長性設定:GRS(Geo冗長ストレージ)
// ledger.backup.drStrategy の方針に基づき、バックアップデータをJapan Westへ
// 自動レプリケーションし、最低限の地理的保全を確保する。
// -----------------------------------------------------------------------------
resource vaultStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-04-01' = {
  parent: recoveryVault
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: 'GeoRedundant'
    crossRegionRestoreFlag: false
  }
}

// -----------------------------------------------------------------------------
// バックアップポリシー:bkp-sanrise-standard-daily
// ・日次バックアップ(毎日02:00、30日間保持)
// ・週次バックアップ(毎週日曜02:00、12週間保持)
// ・月次バックアップ(月初の日曜02:00相当、12ヶ月保持)
// これはVM全体(IaasVMバックアップ)のポリシーであり、ledgerが求めるDBサーバーの
// トランザクションログバックアップ(15分間隔)は、このポリシーとは別に
// SQL Server workload backup(AzureWorkload)として構成する必要がある(下記コメント参照)。
// -----------------------------------------------------------------------------
resource backupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-04-01' = {
  parent: recoveryVault
  name: 'bkp-sanrise-standard-daily'
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
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
      monthlySchedule: {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Months'
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// バックアップ保護対象の登録(5台のVM全てをbkp-sanrise-standard-dailyポリシーで保護)
// Azure Backupでは、コンテナ名・保護アイテム名を
// "iaasvmcontainer;iaasvmcontainerv2;<リソースグループ名>;<VM名>" の形式で
// 組み立てることで、フェイルオーバーやコンテナ登録を暗黙的に行うことができる。
// -----------------------------------------------------------------------------
resource protectedItems 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-04-01' = [for (vmName, i) in vmNames: {
  name: '${recoveryVault.name}/Azure/iaasvmcontainer;iaasvmcontainerv2;${currentResourceGroupName};${vmName}/vm;iaasvmcontainerv2;${currentResourceGroupName};${vmName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    policyId: backupPolicy.id
    sourceResourceId: vmIds[i]
  }
}]

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】
// ・vm-db01:SQL Server IaaS Agent拡張機能の有効化とSQL Serverワークロードの
//   Recovery Services Vaultへの登録(Register-AzRecoveryServicesBackupContainer等)
// ・vm-db01用のAzureWorkloadバックアップポリシーの作成
//   (フルバックアップ週1回・差分バックアップ日次・トランザクションログバックアップ
//    15分間隔、ログ保持15日間)。これはSQL Server on Azure VM向けの専用リソース
//    構成となるため、SQL VMの登録後にAzure Portal/CLI/PowerShellで追加すること。
// ・初回バックアップ実行後のリストア検証(ファイルレベル/VM全体)、DR訓練の実施
// -----------------------------------------------------------------------------

output recoveryVaultId string = recoveryVault.id
output recoveryVaultName string = recoveryVault.name
