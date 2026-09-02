// =============================================================================
// main.bicep
// =============================================================================
// ★★★ 重要:これは学習・ポートフォリオ用の参考実装(サンプルコード)です ★★★
// -----------------------------------------------------------------------------
// 本コードは、株式会社サンライズ物産の基幹サーバー更新プロジェクトを題材とした
// 「設計台帳(ledger)」の内容をAzure Bicepで表現した学習・ポートフォリオ用の
// サンプルであり、そのまま本番環境へ適用することを想定したものではありません。
//
// 実際の環境へデプロイする前に、必ず以下の検証を行ってください。
//   1) az bicep build --file main.bicep         … 構文エラーがないかの確認
//   2) az deployment group validate ...          … デプロイ内容の事前検証
//   3) az deployment group what-if ...           … 実際に作成/変更される
//                                                    リソースの差分確認
//   4) 料金・可用性・セキュリティ要件が自社のポリシーに合致しているかのレビュー
//
// また、パスワード等の機密値は必ず @secure() パラメータや Key Vault 参照など
// 安全な方法で受け渡し、コマンド履歴やソース管理に平文で残さないようにしてください。
// =============================================================================

// このテンプレートはリソースグループスコープでデプロイする前提。
// (targetScopeを明示しない場合、Bicepの既定値は 'resourceGroup' となる)
// デプロイ先のリソースグループ(rg-sanrise-prod-jpe)は事前に作成しておくこと。
targetScope = 'resourceGroup'

// -----------------------------------------------------------------------------
// パラメータ定義
// -----------------------------------------------------------------------------

@description('リソースをデプロイするAzureリージョン。ledgerの制約により japaneast 固定')
param location string = 'japaneast'

@description('全VM共通のローカル管理者アカウント名')
param adminUsername string

@description('全VM共通のローカル管理者パスワード。@secure()によりログや出力に平文表示されない。このパラメータの値はコマンドライン直書きではなく、Key Vault参照やパラメータファイル+実行時プロンプト等で渡すこと')
@secure()
param adminPassword string

@description('SQL Server サービスアカウント(sa相当)のパスワード。@secure()で保護し、Key Vaultへ保存する')
@secure()
param sqlServiceAccountPassword string

@description('監視アラートの通知先メールアドレス(運用担当者宛)')
param alertEmailAddress string

@description('Key Vaultにシークレット書き込み権限(Key Vault Secrets Officer相当)を付与するEntra IDオブジェクトID。空文字の場合はロール割り当てをスキップするため、デプロイ前後で手動で権限を付与すること')
param keyVaultAdministratorObjectId string = ''

// -----------------------------------------------------------------------------
// モジュール1:ネットワーク基盤(VNet / サブネット / NSG)
// -----------------------------------------------------------------------------
module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    location: location
  }
}

// -----------------------------------------------------------------------------
// モジュール2:セキュリティ基盤(Azure Bastion / Key Vault)
// AzureBastionSubnetのIDはnetworkモジュールの出力を利用する
// -----------------------------------------------------------------------------
module security 'modules/security.bicep' = {
  name: 'deploy-security'
  params: {
    location: location
    bastionSubnetId: network.outputs.snetBastionId
    adminPassword: adminPassword
    sqlServiceAccountPassword: sqlServiceAccountPassword
    keyVaultAdministratorObjectId: keyVaultAdministratorObjectId
  }
}

// -----------------------------------------------------------------------------
// モジュール3:コンピューティング(5台のVM + NIC)
// 各層のサブネットIDはnetworkモジュールの出力を利用する
// -----------------------------------------------------------------------------
module compute 'modules/compute.bicep' = {
  name: 'deploy-compute'
  params: {
    location: location
    adminUsername: adminUsername
    adminPassword: adminPassword
    snetWebId: network.outputs.snetWebId
    snetApId: network.outputs.snetApId
    snetDbId: network.outputs.snetDbId
    snetMgmtId: network.outputs.snetMgmtId
  }
}

// -----------------------------------------------------------------------------
// モジュール4:バックアップ(Recovery Services Vault / バックアップポリシー)
// computeモジュールが作成したVMのID一覧をバックアップ保護対象として渡す
// -----------------------------------------------------------------------------
module backup 'modules/backup.bicep' = {
  name: 'deploy-backup'
  params: {
    location: location
    vmNames: compute.outputs.vmNames
    vmIds: compute.outputs.vmIds
  }
}

// -----------------------------------------------------------------------------
// モジュール5:監視(Log Analytics / アラート)
// backupモジュールでRecovery Services Vaultが作成された後に実行することで、
// バックアップ失敗アラート用の診断設定(RSV→Log Analytics)を確実に構成できる
// -----------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    location: location
    vmNames: compute.outputs.vmNames
    vmIds: compute.outputs.vmIds
    alertEmailAddress: alertEmailAddress
  }
  dependsOn: [
    backup
    security
  ]
}

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】(本Bicepテンプレートのスコープ外)
// ・Microsoft Entra IDでの管理者ロール割り当て、条件付きアクセス・MFAポリシー設定
// ・vm-ad01のADドメインコントローラ昇格、DNS構成
// ・vm-web01/vm-ap01への既存業務アプリケーションの移設・動作確認
// ・vm-db01のSQL Server初期構成、TDE有効化と証明書のKey Vaultバックアップ、
//   SQL Server workloadバックアップ(トランザクションログ15分間隔)の登録
// ・vm-file01の共有フォルダ作成とデータ移行
// ・Azure Bastion経由の実際の接続確認(RDP)
// ・Microsoft Defender for Cloud(Defender for Servers)のサブスクリプション
//   スコープでの有効化
// ・初回バックアップ完了後のリストア検証・DR訓練の実施
// 詳細は各モジュールファイル内のコメントも参照すること。
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// 出力(デプロイ後の確認や後続作業に利用)
// -----------------------------------------------------------------------------
output vnetName string = network.outputs.vnetName
output keyVaultName string = security.outputs.keyVaultName
output bastionId string = security.outputs.bastionId
output vmNames array = compute.outputs.vmNames
output recoveryVaultName string = backup.outputs.recoveryVaultName
output logAnalyticsWorkspaceName string = monitoring.outputs.logAnalyticsWorkspaceName
