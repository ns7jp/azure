// =============================================================================
// modules/compute.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// 設計台帳(ledger.servers)に定義された5台のWindows仮想マシン(VM)と、
// それぞれに対応するNIC(ネットワークインターフェース)を作成する。
//
// 重要なポイント:
// ・全VMのNICにはパブリックIPアドレスを一切割り当てない
//   (管理アクセスは modules/security.bicep で作成したAzure Bastion経由のみ)
// ・各VMのプライベートIPアドレスはledgerの値に合わせて静的に固定する
// ・VMサイズはコスト抑制のためBシリーズ(バースト可能インスタンス)を基本とする
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string = 'japaneast'

@description('全VM共通のローカル管理者アカウント名')
param adminUsername string

@description('全VM共通のローカル管理者パスワード(Key Vaultに保存した値と同一にすること)')
@secure()
param adminPassword string

@description('Web層サブネット(snet-web-prod-jpe)のリソースID')
param snetWebId string

@description('AP層サブネット(snet-ap-prod-jpe)のリソースID')
param snetApId string

@description('DB層サブネット(snet-db-prod-jpe)のリソースID')
param snetDbId string

@description('管理用サブネット(snet-mgmt-prod-jpe)のリソースID')
param snetMgmtId string

// -----------------------------------------------------------------------------
// 共通のWindows Server 2022 Datacenterイメージ参照(Web/AP/AD/ファイルサーバー用)
// -----------------------------------------------------------------------------
var windowsServer2022Image = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-azure-edition'
  version: 'latest'
}

// vm-db01専用:SQL Server 2022 Standard Edition搭載済みのWindows Server 2022イメージ
// (Azure Marketplaceの"SQL Server 2022 on Windows Server 2022"イメージを使用)
var sqlServer2022Image = {
  publisher: 'MicrosoftSQLServer'
  offer: 'sql2022-ws2022'
  sku: 'standard-gen2'
  version: 'latest'
}

// SQL ServerのMarketplaceイメージはプラン(purchase plan)情報が必要になる場合がある。
// 【手動またはスクリプトでの追加作業が必要】初回デプロイ前に以下のコマンド等で
// Marketplaceの利用条件に同意しておくこと(未同意の場合はVM作成が失敗する):
//   az vm image terms accept --publisher MicrosoftSQLServer --offer sql2022-ws2022 --plan standard-gen2
var sqlServer2022Plan = {
  name: 'standard-gen2'
  publisher: 'MicrosoftSQLServer'
  product: 'sql2022-ws2022'
}

// -----------------------------------------------------------------------------
// ディスクサイズについての補足コメント:
// ledgerでは "Standard SSD(E6)" "Standard SSD(E10)" のようにAzureのディスク
// 課金単位(Eシリーズ)で記載されている。E6=64GiB、E10=128GiBに相当するため、
// 本コードではその対応関係に基づきディスクサイズ(diskSizeGB)を設定している。
// DBサーバーのデータ/ログ/tempdb用Premium SSDについてはledgerに具体的な
// サイズの明記がないため、学習用途として128GiB(P10相当)を仮定している。
// 実運用では想定データ量に応じて必ず見直すこと。
// -----------------------------------------------------------------------------
var standardSsdE6GB = 64
var standardSsdE10GB = 128
var premiumSsdAssumedGB = 128

// -----------------------------------------------------------------------------
// サブネット名 -> サブネットIDの対応表(ledger.servers[].subnet の値をキーにする)
// -----------------------------------------------------------------------------
var subnetIdMap = {
  'snet-web-prod-jpe': snetWebId
  'snet-ap-prod-jpe': snetApId
  'snet-db-prod-jpe': snetDbId
  'snet-mgmt-prod-jpe': snetMgmtId
}

// -----------------------------------------------------------------------------
// VM定義一覧(ledger.serversの値をそのまま反映)
// dataDisksが空配列のVMは追加データディスクなし。
// -----------------------------------------------------------------------------
var servers = [
  {
    name: 'vm-ad01'
    vmSize: 'Standard_B2ms'
    subnetKey: 'snet-mgmt-prod-jpe'
    privateIp: '10.10.4.4'
    osDiskType: 'StandardSSD_LRS'
    osDiskSizeGB: standardSsdE10GB
    image: windowsServer2022Image
    plan: null
    dataDisks: []
  }
  {
    name: 'vm-web01'
    vmSize: 'Standard_B2s'
    subnetKey: 'snet-web-prod-jpe'
    privateIp: '10.10.1.4'
    osDiskType: 'StandardSSD_LRS'
    osDiskSizeGB: standardSsdE6GB
    image: windowsServer2022Image
    plan: null
    dataDisks: []
  }
  {
    name: 'vm-ap01'
    vmSize: 'Standard_B2ms'
    subnetKey: 'snet-ap-prod-jpe'
    privateIp: '10.10.2.4'
    osDiskType: 'StandardSSD_LRS'
    osDiskSizeGB: standardSsdE10GB
    image: windowsServer2022Image
    plan: null
    dataDisks: []
  }
  {
    name: 'vm-db01'
    vmSize: 'Standard_B4ms'
    subnetKey: 'snet-db-prod-jpe'
    privateIp: '10.10.3.4'
    osDiskType: 'StandardSSD_LRS'
    osDiskSizeGB: standardSsdE10GB
    image: sqlServer2022Image
    plan: sqlServer2022Plan
    // SQL Serverのデータ/ログ/tempdbを分離するための追加Premium SSDディスク3本
    dataDisks: [
      {
        lun: 0
        nameSuffix: 'sqldata'
        diskType: 'Premium_LRS'
        diskSizeGB: premiumSsdAssumedGB
      }
      {
        lun: 1
        nameSuffix: 'sqllog'
        diskType: 'Premium_LRS'
        diskSizeGB: premiumSsdAssumedGB
      }
      {
        lun: 2
        nameSuffix: 'tempdb'
        diskType: 'Premium_LRS'
        diskSizeGB: premiumSsdAssumedGB
      }
    ]
  }
  {
    name: 'vm-file01'
    vmSize: 'Standard_B2s'
    subnetKey: 'snet-mgmt-prod-jpe'
    privateIp: '10.10.4.5'
    osDiskType: 'StandardSSD_LRS'
    osDiskSizeGB: standardSsdE6GB
    image: windowsServer2022Image
    plan: null
    // 部門共有・帳票データ保管用の追加データディスク(Standard SSD E6相当)
    dataDisks: [
      {
        lun: 0
        nameSuffix: 'data'
        diskType: 'StandardSSD_LRS'
        diskSizeGB: standardSsdE6GB
      }
    ]
  }
]

// -----------------------------------------------------------------------------
// NIC(ネットワークインターフェース)一式
// ipConfigurationsにpublicIPAddressを指定しない = パブリックIPなしのNIC
// -----------------------------------------------------------------------------
resource nics 'Microsoft.Network/networkInterfaces@2023-11-01' = [for server in servers: {
  name: 'nic-${server.name}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: server.privateIp
          subnet: {
            id: subnetIdMap[server.subnetKey]
          }
          // publicIPAddress プロパティを指定しないことで、パブリックIPを持たせない
        }
      }
    ]
    enableIPForwarding: false
  }
}]

// -----------------------------------------------------------------------------
// 仮想マシン本体
// ・licenseType 'Windows_Server' でAzureハイブリッド特典(該当する場合)を利用可能にする
// ・bootDiagnosticsはマネージドストレージを使用してシンプルに有効化
// -----------------------------------------------------------------------------
resource vms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for (server, i) in servers: {
  name: server.name
  location: location
  // vm-db01のみMarketplaceイメージのプラン情報(plan)を設定する。他のVMはnull(プランなし)。
  plan: server.plan
  properties: {
    hardwareProfile: {
      vmSize: server.vmSize
    }
    osProfile: {
      computerName: server.name
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: server.image
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: server.osDiskType
        }
        diskSizeGB: server.osDiskSizeGB
      }
      dataDisks: [for disk in server.dataDisks: {
        lun: disk.lun
        createOption: 'Empty'
        diskSizeGB: disk.diskSizeGB
        managedDisk: {
          storageAccountType: disk.diskType
        }
      }]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nics[i].id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
    licenseType: 'Windows_Server'
  }
}]

// -----------------------------------------------------------------------------
// 【手動またはスクリプトでの追加作業が必要】(IaCだけでは完結しない作業)
// ・vm-ad01:オンプレミスADドメイン(sanrise.local)への昇格・レプリカドメイン
//   コントローラ構築、DNS役割の設定(dcpromo/Install-ADDSDomainController)
// ・vm-web01/vm-ap01:各VMのドメイン参加、IIS/.NET Framework/業務アプリケーションの
//   インストールと構成(既存システムからの移行作業)
// ・vm-db01:SQL Server 2022の初期構成、TDE(透過的データ暗号化)の有効化と
//   証明書のエクスポート・Key Vaultへのバックアップ保管
// ・vm-file01:SMB共有フォルダの作成・共有権限設定、既存ファイルサーバーからの
//   データ移行
// ・全VM共通:Azure Bastion経由でのRDP接続確認、Windows Updateの適用状況確認
// これらはPowerShell DSCやCustom Script Extension、Azure Automation等を用いた
// 別フェーズでの自動化を推奨する(本テンプレートのスコープ外)。
// -----------------------------------------------------------------------------

output vmNames array = [for server in servers: server.name]
output vmIds array = [for (server, i) in servers: vms[i].id]
