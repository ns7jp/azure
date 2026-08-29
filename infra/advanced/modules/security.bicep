// =============================================================================
// modules/security.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// ・Azure Bastion(パブリックIP付与なしでVMへ安全に接続するための踏み台サービス)
// ・Azure Key Vault(管理者パスワード等の機密情報を一元管理する金庫)
// を作成する。
//
// VM自体にはパブリックIPを一切付与せず、管理者は必ずAzure Bastion経由で
// 接続する構成とすることで、固定グローバルIP経由の直接RDPという既存課題を解消する。
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string = 'japaneast'

@description('Azure Bastionを配置するAzureBastionSubnetのサブネットID(network.bicepの出力を渡す)')
param bastionSubnetId string

@description('VMのローカル管理者(Administrator)パスワード。Key Vaultにシークレットとして保存する')
@secure()
param adminPassword string

@description('SQL Server サービスアカウント(sa相当)のパスワード。Key Vaultにシークレットとして保存する')
@secure()
param sqlServiceAccountPassword string

@description('Key Vaultに対してシークレットの管理権限(Key Vault Secrets Officer相当)を付与するEntra IDのオブジェクトID。'
  + '空文字の場合はロール割り当てをスキップする(後から手動でアクセス権を付与すること)')
param keyVaultAdministratorObjectId string = ''

// -----------------------------------------------------------------------------
// Key Vault(kv-sanrise-prod-jpe)
// ・RBAC(ロールベースアクセス制御)によりアクセスを統制する(アクセスポリシー方式ではなくRBACを採用)
// ・削除保護のためソフトデリート・パージ保護を有効化(学習用のため保持期間は既定値90日)
// -----------------------------------------------------------------------------
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-sanrise-prod-jpe'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true // Microsoft Entra IDのRBACでアクセスを最小権限に統制
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled' // 学習用途のため既定値。本番ではPrivate Endpoint化を推奨
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// -----------------------------------------------------------------------------
// Key Vaultへのロール割り当て(任意)
// enableRbacAuthorization: true の場合、シークレットの作成にはRBACロールが必要。
// このBicepデプロイを実行するプリンシパル(利用者やパイプライン)自身が
// シークレットを書き込めるよう、"Key Vault Secrets Officer" ロールを付与する。
// keyVaultAdministratorObjectId が指定されなかった場合はスキップされるため、
// その場合はデプロイ前に手動でロールを付与しておくこと。
// -----------------------------------------------------------------------------
resource keyVaultSecretsOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(keyVaultAdministratorObjectId)) {
  name: guid(keyVault.id, keyVaultAdministratorObjectId, 'KeyVaultSecretsOfficer')
  scope: keyVault
  properties: {
    // 組み込みロール "Key Vault Secrets Officer" のロール定義ID
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: keyVaultAdministratorObjectId
    principalType: 'User'
  }
}

// -----------------------------------------------------------------------------
// シークレット1:VMローカル管理者パスワード
// 手動作業メモ:各VMのAdministratorパスワードは本シークレットの値と一致させること。
// アプリケーションやスクリプトから接続文字列等を参照する際は、コード直書きせず
// 必ずこのKey Vaultから取得する運用とする。
// -----------------------------------------------------------------------------
resource secretVmAdminPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'vm-local-admin-password'
  properties: {
    value: adminPassword
  }
}

// -----------------------------------------------------------------------------
// シークレット2:SQL Serverサービスアカウント(sa相当)パスワード
// vm-db01上のSQL Server 2022のサービスアカウント/sa相当アカウントのパスワードを
// ここに保存し、APサーバーからの接続文字列もこのシークレットを参照する想定。
// -----------------------------------------------------------------------------
resource secretSqlServiceAccountPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-service-account-password'
  properties: {
    value: sqlServiceAccountPassword
  }
}

// -----------------------------------------------------------------------------
// Azure Bastion用パブリックIP(Standard SKU、静的割り当てが必須)
// パブリックIPを持つのはこのBastion用IPのみであり、業務VM側には一切付与しない。
// -----------------------------------------------------------------------------
resource bastionPublicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-bas-sanrise-prod-jpe'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// -----------------------------------------------------------------------------
// Azure Bastion(bas-sanrise-prod-jpe、Basic SKU)
// 社内の管理者はAzure Portal経由でこのBastionを使い、パブリックIPを持たない
// 各VMへRDP接続する。接続にはMicrosoft Entra IDのサインイン(MFA必須)を利用する想定。
// -----------------------------------------------------------------------------
resource bastionHost 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'bas-sanrise-prod-jpe'
  location: location
  sku: {
    name: 'Basic' // コスト重視のためBasic SKUを採用(ネイティブクライアント対応等が必要な場合はStandardへ変更)
  }
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: bastionPublicIp.id
          }
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】
// ・Bastion経由でのVM接続確認(実際にPortalからRDP接続できるかのテスト)
// ・Entra ID側での管理者ロール割り当て、条件付きアクセス・MFAポリシーの設定
//   (Entra ID条件付きアクセスはBicep/ARMの一般的なリソースでは表現しないため、
//    Entra管理センターまたはMicrosoft Graph PowerShell/CLIで別途構成すること)
// -----------------------------------------------------------------------------

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
output bastionId string = bastionHost.id
