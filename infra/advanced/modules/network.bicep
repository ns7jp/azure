// =============================================================================
// modules/network.bicep
// -----------------------------------------------------------------------------
// 【このファイルの役割】
// 仮想ネットワーク(VNet)、5つのサブネット、各サブネット用のネットワーク
// セキュリティグループ(NSG)とそのルール、NSGとサブネットの関連付けを作成する。
//
// 設計台帳(ledger)の network / nsgRules セクションの値をそのまま使用しており、
// リソース名・CIDR・ポート番号などは架空の値に変更していない。
// =============================================================================

@description('リソースをデプロイするAzureリージョン')
param location string = 'japaneast'

// -----------------------------------------------------------------------------
// 変数定義:VNet / サブネットの構成(ledger.network の値をそのまま使用)
// -----------------------------------------------------------------------------
var vnetName = 'vnet-sanrise-prod-jpe'
var vnetAddressPrefix = '10.10.0.0/16'

// サブネットごとのCIDR(ledger.network.subnets の値)
var snetWebPrefix = '10.10.1.0/24'
var snetApPrefix = '10.10.2.0/24'
var snetDbPrefix = '10.10.3.0/24'
var snetMgmtPrefix = '10.10.4.0/24'
var snetBastionPrefix = '10.10.5.0/26'

// -----------------------------------------------------------------------------
// NSG: nsg-bastion-prod-jpe (AzureBastionSubnet 用)
// Azure Bastionを正しく動作させるために"公式に必須"とされているルール一式。
// 優先度・ポート番号はMicrosoft公式ドキュメントの必須ルールに準拠している。
// -----------------------------------------------------------------------------
resource nsgBastion 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-bastion-prod-jpe'
  location: location
  properties: {
    securityRules: [
      {
        // インターネットからBastionへのHTTPS(443)受信を許可(Bastion利用者からの接続)
        name: 'AllowHttpsInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: snetBastionPrefix
        }
      }
      {
        // Azure基盤の管理トラフィック(GatewayManager)を許可(Bastion必須ルール)
        name: 'AllowGatewayManagerInbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: snetBastionPrefix
        }
      }
      {
        // ヘルスプローブ用にAzureLoadBalancerからの通信を許可(Bastion必須ルール)
        name: 'AllowAzureLoadBalancerInbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: snetBastionPrefix
        }
      }
      {
        // Bastionホスト間のデータプレーン内部通信を許可(Bastion必須ルール)
        name: 'AllowBastionHostCommunicationInbound'
        properties: {
          priority: 130
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetBastionPrefix
        }
      }
      {
        // 上記以外のインバウンド通信は既定で全て拒否することを明示化
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        // Bastionから対象VNet内VMへの踏み台RDP/SSH通信を許可(Bastion必須ルール)
        name: 'AllowSshRdpOutbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '22'
            '3389'
          ]
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: vnetAddressPrefix
        }
      }
      {
        // 証明書検証やログ等、Azure基盤サービスへのHTTPS送信を許可(Bastion必須ルール)
        name: 'AllowAzureCloudOutbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: 'AzureCloud'
        }
      }
      {
        // Bastionホスト間のデータプレーン内部通信を許可(Bastion必須ルール、送信方向)
        name: 'AllowBastionHostCommunicationOutbound'
        properties: {
          priority: 120
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '8080'
            '5701'
          ]
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetBastionPrefix
        }
      }
      {
        // セッション情報取得のためのHTTP(80)送信を許可(Bastion必須ルール)
        name: 'AllowGetSessionInformationOutbound'
        properties: {
          priority: 130
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: 'Internet'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// NSG: nsg-web-prod-jpe (Web層サブネット用)
// 社内イントラネットからのHTTPSアクセスとBastion経由の管理接続のみを許可し、
// インターネットからの直接アクセスとDB層への直接通信を明示的に拒否する。
// -----------------------------------------------------------------------------
resource nsgWeb 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-web-prod-jpe'
  location: location
  properties: {
    securityRules: [
      {
        // Bastion経由の管理アクセスのみ許可し、直接のRDP接続を禁止(ゼロトラスト)
        name: 'Allow-Bastion-Rdp-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetWebPrefix
        }
      }
      {
        // 社内ユーザー端末からの受発注・在庫管理システムWeb画面アクセスのみ許可
        name: 'Allow-CorpIntranet-Https-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '172.16.0.0/16'
          destinationAddressPrefix: snetWebPrefix
        }
      }
      {
        // インターネットからの直接アクセスを遮断し、社内利用のみに限定する
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: snetWebPrefix
        }
      }
      {
        // Web層からAP層へのアプリケーションAPI呼び出しのみ許可(8443番ポート)
        name: 'Allow-Web-To-Ap-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8443'
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetApPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(TCP版)
        // 補足:ledgerでは1本のルールに"TCP,UDP"と記載されているが、Azure NSGの
        // 1ルールには単一プロトコルしか指定できない仕様のため、TCP/UDPの2ルールに
        // 分割している(優先度は110/111として隣接させ、意味合いを維持)。
        name: 'Allow-Web-To-AdDns-Outbound-Tcp'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(UDP版。上記コメント参照)
        name: 'Allow-Web-To-AdDns-Outbound-Udp'
        properties: {
          priority: 111
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // 多層防御:Web層からDB層への直接通信を明示的に禁止する
        name: 'Deny-Web-To-Db-Outbound'
        properties: {
          priority: 200
          direction: 'Outbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetDbPrefix
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// NSG: nsg-ap-prod-jpe (AP層サブネット用)
// Web層からのAPI呼び出しとBastion経由の管理接続のみを許可し、DB層からの
// 逆方向通信を拒否する多層防御構成。
// -----------------------------------------------------------------------------
resource nsgAp 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-ap-prod-jpe'
  location: location
  properties: {
    securityRules: [
      {
        // Web層からの業務アプリケーションAPI呼び出しのみ許可
        name: 'Allow-Web-To-Ap-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8443'
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetApPrefix
        }
      }
      {
        // Bastion経由の管理アクセスのみ許可
        name: 'Allow-Bastion-Rdp-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetApPrefix
        }
      }
      {
        // 多層防御:DB層からAP層への逆方向の通信開始を禁止
        name: 'Deny-Db-To-Ap-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: snetDbPrefix
          destinationAddressPrefix: snetApPrefix
        }
      }
      {
        // APサーバーからDBサーバーへのSQL接続(1433番)のみ許可
        name: 'Allow-Ap-To-Db-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: snetApPrefix
          destinationAddressPrefix: snetDbPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(TCP版。分割理由はWeb層NSGのコメント参照)
        name: 'Allow-Ap-To-AdDns-Outbound-Tcp'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetApPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(UDP版)
        name: 'Allow-Ap-To-AdDns-Outbound-Udp'
        properties: {
          priority: 111
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetApPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// NSG: nsg-db-prod-jpe (DB層サブネット用)
// APサーバーからの1433番ポート接続とBastion経由の管理接続のみを許可し、
// Web層からの直接アクセスを拒否する。
// -----------------------------------------------------------------------------
resource nsgDb 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-db-prod-jpe'
  location: location
  properties: {
    securityRules: [
      {
        // APサーバーからのSQL接続のみ許可し、他層からの接続を遮断する
        name: 'Allow-Ap-To-Db-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: snetApPrefix
          destinationAddressPrefix: snetDbPrefix
        }
      }
      {
        // Bastion経由の管理アクセスのみ許可
        name: 'Allow-Bastion-Rdp-Inbound'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetDbPrefix
        }
      }
      {
        // 多層防御:Web層からDB層への直接アクセスを明示的に遮断する
        name: 'Deny-Web-To-Db-Inbound'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: snetWebPrefix
          destinationAddressPrefix: snetDbPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(TCP版。分割理由はWeb層NSGのコメント参照)
        name: 'Allow-Db-To-AdDns-Outbound-Tcp'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetDbPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // 名前解決とドメイン認証のためADサーバーへの通信のみ許可(UDP版)
        name: 'Allow-Db-To-AdDns-Outbound-Udp'
        properties: {
          priority: 101
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
          ]
          sourceAddressPrefix: snetDbPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // Azure Backup(MARSエージェント/バックアップ拡張機能)によるバックアップデータの
        // Azure Storageへの送信を許可(サービスタグ Storage を使用)
        name: 'Allow-Db-To-AzureBackup-Outbound'
        properties: {
          priority: 110
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: snetDbPrefix
          destinationAddressPrefix: 'Storage'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// NSG: nsg-mgmt-prod-jpe (管理用サブネット:AD DS/DNS、ファイルサーバー用)
// VNet全体からのAD/DNS/SMBアクセスとBastion経由の管理接続のみを許可し、
// インターネットからの直接アクセスを拒否する。
// -----------------------------------------------------------------------------
resource nsgMgmt 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-mgmt-prod-jpe'
  location: location
  properties: {
    securityRules: [
      {
        // Bastion経由の管理アクセスのみ許可
        name: 'Allow-Bastion-Rdp-Inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: snetBastionPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // Web/AP/DB各層からのDNS名前解決・AD認証・SMBファイル共有アクセスを許可(TCP版。分割理由は上記参照)
        name: 'Allow-VNet-To-AdDns-Inbound-Tcp'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
            '3268'
          ]
          sourceAddressPrefix: vnetAddressPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // Web/AP/DB各層からのDNS名前解決・AD認証・SMBファイル共有アクセスを許可(UDP版)
        name: 'Allow-VNet-To-AdDns-Inbound-Udp'
        properties: {
          priority: 111
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRanges: [
            '53'
            '88'
            '389'
            '445'
            '3268'
          ]
          sourceAddressPrefix: vnetAddressPrefix
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // インターネットからの直接アクセスを遮断する
        name: 'Deny-Internet-Inbound'
        properties: {
          priority: 4000
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'Internet'
          destinationAddressPrefix: snetMgmtPrefix
        }
      }
      {
        // Entra Connectによるディレクトリ同期のためのHTTPS通信を許可(サービスタグ AzureActiveDirectory)
        name: 'Allow-Mgmt-To-EntraId-Outbound'
        properties: {
          priority: 100
          direction: 'Outbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: snetMgmtPrefix
          destinationAddressPrefix: 'AzureActiveDirectory'
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// VNet + サブネット本体
// 各サブネットのproperties.networkSecurityGroupで対応するNSGを直接関連付けている。
// (Bicepではサブネット定義内でNSGを指定するだけで関連付けが完了する)
// -----------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        // Web層(IISによる受発注・在庫管理システムのフロントエンド)
        name: 'snet-web-prod-jpe'
        properties: {
          addressPrefix: snetWebPrefix
          networkSecurityGroup: {
            id: nsgWeb.id
          }
        }
      }
      {
        // AP層(業務アプリケーションサーバー、受発注・在庫管理ロジック実行)
        name: 'snet-ap-prod-jpe'
        properties: {
          addressPrefix: snetApPrefix
          networkSecurityGroup: {
            id: nsgAp.id
          }
        }
      }
      {
        // DB層(SQL Serverによるデータベースサーバー)
        name: 'snet-db-prod-jpe'
        properties: {
          addressPrefix: snetDbPrefix
          networkSecurityGroup: {
            id: nsgDb.id
          }
        }
      }
      {
        // 管理用サブネット(AD DS/DNS、ファイルサーバー等の基盤系サーバー)
        name: 'snet-mgmt-prod-jpe'
        properties: {
          addressPrefix: snetMgmtPrefix
          networkSecurityGroup: {
            id: nsgMgmt.id
          }
        }
      }
      {
        // Azure Bastion専用サブネット。名称は"AzureBastionSubnet"固定(Azureの仕様)
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: snetBastionPrefix
          networkSecurityGroup: {
            id: nsgBastion.id
          }
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// 出力:他モジュール(security / compute)がサブネットIDを参照できるようにする
// -----------------------------------------------------------------------------
output vnetId string = vnet.id
output vnetName string = vnet.name

output snetWebId string = vnet.properties.subnets[0].id
output snetApId string = vnet.properties.subnets[1].id
output snetDbId string = vnet.properties.subnets[2].id
output snetMgmtId string = vnet.properties.subnets[3].id
output snetBastionId string = vnet.properties.subnets[4].id
