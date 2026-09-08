// =============================================================================
// modules/monitoring.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// ・Log Analyticsワークスペース(log-sanrise-prod-jpe)の作成
// ・各VMからCPU/ディスク等のメトリックを収集するためのデータ収集ルール(DCR)と
//   Azure Monitor エージェント(AMA)拡張機能の展開
// ・Key Vault / Azure Bastion / Recovery Services Vaultの診断設定(ログ転送)
// ・Action Group(ag-sanrise-ops)とアラートルール一式
//
// これにより、担当者の目視確認に頼っていた監視体制を、CPU/ディスク逼迫や
// VM停止、バックアップ失敗を自動検知して通知する体制へ置き換える。
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string = 'japaneast'

@description('監視対象VMの名前一覧(compute.bicepの出力を渡す)')
param vmNames array

@description('監視対象VMのリソースID一覧(compute.bicepの出力を渡す。vmNamesと同じ並び順であること)')
param vmIds array

@description('アラート通知先メールアドレス(運用担当者)')
param alertEmailAddress string

// security.bicep / backup.bicep で作成済みのリソース名(ledgerの固定値)
// ID文字列を跨いで受け渡す代わりに、同一リソースグループ内の既存リソースとして参照する
var keyVaultName = 'kv-sanrise-prod-jpe'
var bastionName = 'bas-sanrise-prod-jpe'
var recoveryVaultName = 'rsv-sanrise-prod-jpe'

// -----------------------------------------------------------------------------
// Log Analyticsワークスペース(log-sanrise-prod-jpe)
// -----------------------------------------------------------------------------
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-sanrise-prod-jpe'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // 従量課金プラン(Pay-As-You-Go)。ledger.cost の想定と一致
    }
    retentionInDays: 30
  }
}

// -----------------------------------------------------------------------------
// データ収集ルール(DCR):各VMのゲストOS内パフォーマンスカウンター
// (CPU使用率、ディスク空き容量、ディスク書き込みレイテンシ)を収集し、
// Log Analyticsワークスペースへ送信する。
// -----------------------------------------------------------------------------
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-sanrise-prod-jpe'
  location: location
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
            '\\LogicalDisk(*)\\% Free Space'
            '\\PhysicalDisk(*)\\Avg. Disk sec/Write'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: logAnalyticsWorkspace.id
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
    ]
  }
}

// -----------------------------------------------------------------------------
// 監視対象VMを「既存リソース」として参照する(compute.bicepで作成済みのため)
// -----------------------------------------------------------------------------
resource existingVms 'Microsoft.Compute/virtualMachines@2023-09-01' existing = [for name in vmNames: {
  name: name
}]

// 各VMにAzure Monitor エージェント(AMA)拡張機能を導入する
// (このエージェントがOS内のパフォーマンスカウンターやHeartbeatをLog Analyticsへ送信する)
resource amaExtensions 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [for (name, i) in vmNames: {
  name: 'AzureMonitorWindowsAgent'
  parent: existingVms[i]
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}]

// 各VMをデータ収集ルールに関連付ける(これによりPerfカウンターの収集が開始される)
resource dcrAssociations 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = [for (name, i) in vmNames: {
  name: 'dcra-${name}'
  scope: existingVms[i]
  properties: {
    dataCollectionRuleId: dcr.id
  }
  dependsOn: [
    amaExtensions[i]
  ]
}]

// -----------------------------------------------------------------------------
// Key Vault / Azure Bastion / Recovery Services Vault の既存リソース参照
// (他モジュールで作成済みのリソースへ診断設定を追加するために参照する)
// -----------------------------------------------------------------------------
resource existingKeyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource existingBastion 'Microsoft.Network/bastionHosts@2023-11-01' existing = {
  name: bastionName
}

resource existingRecoveryVault 'Microsoft.RecoveryServices/vaults@2023-04-01' existing = {
  name: recoveryVaultName
}

// Key Vaultの監査ログをLog Analyticsへ転送(シークレットへのアクセス操作の証跡確保)
// diagnosticSettings@2021-05-01 はBicepの型情報が未提供のため BCP081 が出るが、
// Azure公式ドキュメントに記載の有効なAPIバージョンであり、デプロイは妨げられない。
#disable-next-line BCP081
resource diagKeyVault 'Microsoft.Insights/diagnosticSettings@2021-05-01' = {
  name: 'diag-to-log-analytics'
  scope: existingKeyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

// Bastionの接続ログ(接続元アカウント・接続先VM・接続時刻)をLog Analyticsへ転送
// ダッシュボード項目「Azure Bastionの接続ログ」の元データとなる
#disable-next-line BCP081
resource diagBastion 'Microsoft.Insights/diagnosticSettings@2021-05-01' = {
  name: 'diag-to-log-analytics'
  scope: existingBastion
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'BastionAuditLogs'
        enabled: true
      }
    ]
  }
}

// Recovery Services Vaultのバックアップジョブ・アラート情報をLog Analyticsへ転送
// (alert-backup-job-failure のクエリアラートのデータソースとなる)
#disable-next-line BCP081
resource diagRecoveryVault 'Microsoft.Insights/diagnosticSettings@2021-05-01' = {
  name: 'diag-to-log-analytics'
  scope: existingRecoveryVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'AddonAzureBackupJobs'
        enabled: true
      }
      {
        category: 'AddonAzureBackupAlerts'
        enabled: true
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// Action Group:ag-sanrise-ops
// メール通知を実装する。Teamsチャネル通知はWebhook URL発行後に
// webhookReceiversを追加する形で拡張できる(発行作業は手動)。
// -----------------------------------------------------------------------------
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-sanrise-ops'
  location: 'global'
  properties: {
    groupShortName: 'sanriseops'
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

// -----------------------------------------------------------------------------
// アラート1:alert-vm-high-cpu
// 各VM(vm-ad01, vm-web01, vm-ap01, vm-db01, vm-file01)のCPU使用率が
// 5分平均で85%を超過した状態が10分以上継続した場合に通知する。
// ホストレベルのメトリック"Percentage CPU"を使う標準的なメトリックアラート。
// -----------------------------------------------------------------------------
resource alertVmHighCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm-high-cpu'
  location: 'global'
  properties: {
    description: '各VMのCPU使用率が5分平均で85%を超過した状態が10分以上継続'
    severity: 2
    enabled: true
    scopes: vmIds
    evaluationFrequency: 'PT5M'
    windowSize: 'PT10M'
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'HighCpu'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// アラート2:alert-disk-low-freespace
// OSディスクまたはデータディスクの空き容量が10%未満になった場合に通知する。
// ゲストOS内のカウンターが必要なため、DCR経由で収集したLog Analyticsの
// Perfテーブル(LogicalDisk % Free Space)を利用したクエリアラートとする。
// 補足:ITSMツールへの自動チケット起票はAzure Monitor単体では行えないため、
// Action GroupのWebhook/Logic Appアクション追加など別途の連携構築が必要
// (【手動またはスクリプトでの追加作業が必要】)。
// -----------------------------------------------------------------------------
resource alertDiskLowFreeSpace 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-disk-low-freespace'
  location: location
  properties: {
    displayName: 'alert-disk-low-freespace'
    description: 'OSディスクまたはデータディスクの空き容量が10%未満'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Perf | where ObjectName == "LogicalDisk" and CounterName == "% Free Space" and InstanceName != "_Total" | summarize AggregatedValue = min(CounterValue) by bin(TimeGenerated, 15m)'
          timeAggregation: 'Minimum'
          operator: 'LessThan'
          threshold: 10
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// アラート3:alert-vm-unavailable
// Log AnalyticsのHeartbeatが5分間欠落し、VMの応答が確認できない状態を検知する。
// -----------------------------------------------------------------------------
resource alertVmUnavailable 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-vm-unavailable'
  location: location
  properties: {
    displayName: 'alert-vm-unavailable'
    description: 'VMのHeartbeatが5分間欠落し、応答が確認できない状態(重大度Sev1)'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Heartbeat | summarize LastHeartbeat = max(TimeGenerated) by Computer | where LastHeartbeat < ago(5m)'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// アラート4:alert-backup-job-failure
// Recovery Services Vault(rsv-sanrise-prod-jpe)のバックアップジョブが
// Failedステータスで完了した場合に通知する(診断設定で転送したログを利用)。
// -----------------------------------------------------------------------------
resource alertBackupJobFailure 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-backup-job-failure'
  location: location
  properties: {
    displayName: 'alert-backup-job-failure'
    description: 'Recovery Services Vaultのバックアップジョブが失敗した'
    severity: 1
    enabled: true
    evaluationFrequency: 'PT30M'
    windowSize: 'PT30M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'AddonAzureBackupJobs | where JobStatus == "Failed"'
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
  dependsOn: [
    diagRecoveryVault
  ]
}

// -----------------------------------------------------------------------------
// アラート5:alert-sql-high-dtu-or-storage
// vm-db01のtempdb格納ディスクの空き容量が15%未満になった場合に通知する。
// 補足:ディスク書き込みレイテンシ(I/O待機時間)による検知は、
// \PhysicalDisk\Avg. Disk sec/Write カウンターの追加分析が必要となるため、
// 本テンプレートでは代表条件として空き容量閾値のみを実装している。
// 実運用時はレイテンシ条件を追加するなど要調整。
// -----------------------------------------------------------------------------
resource alertSqlDiskOrStorage 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-high-dtu-or-storage'
  location: location
  properties: {
    displayName: 'alert-sql-high-dtu-or-storage'
    description: 'vm-db01のtempdb格納ディスクの空き容量が15%未満'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT15M'
    windowSize: 'PT15M'
    scopes: [
      logAnalyticsWorkspace.id
    ]
    criteria: {
      allOf: [
        {
          query: 'Perf | where Computer contains "vm-db01" and ObjectName == "LogicalDisk" and CounterName == "% Free Space" | summarize AggregatedValue = min(CounterValue) by bin(TimeGenerated, 15m)'
          timeAggregation: 'Minimum'
          operator: 'LessThan'
          threshold: 15
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】
// ・Microsoft Defender for Cloud(Defender for Servers プラン)はサブスクリプション
//   スコープのリソース(Microsoft.Security/pricings)であり、リソースグループ
//   スコープの本テンプレートには含められない。有効化は
//   `az security pricing create --name VirtualMachines --tier Standard` 等の
//   サブスクリプションスコープの操作、またはAzure Portalで別途行うこと。
// ・NSGフローログ/Traffic Analytics(ダッシュボード項目)は、Network Watcherと
//   フローログ保存用ストレージアカウントが別途必要となるため本テンプレートの
//   スコープ外としている。将来的な拡張候補。
// ・Azure Monitorダッシュボード(ブック/Workbook)自体の作成・共有はPortal上での
//   作業を推奨(本テンプレートはデータソースとアラートの土台のみを提供する)。
// -----------------------------------------------------------------------------

output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name
output actionGroupId string = actionGroup.id
