# 04. 詳細設計書（パラメーターシート）

## 共通

| 項目 | 値 | 理由 |
|---|---|---|
| location | `japaneast` | 想定利用者に近いリージョン |
| environment | `dev` | 学習・開発環境 |
| projectName | `portfolio` | 用途を識別 |
| owner | 任意の非機密識別子 | コストと管理責任の追跡 |
| resourceGroup | `rg-portfolio-dev-jpe-001` | 一括管理・削除 |

## ネットワーク

| リソース | 設定 |
|---|---|
| VNet | `10.20.0.0/16` |
| Server Subnet | `10.20.1.0/24` |
| Public IP | Standard / Static |
| SSH受信 | TCP/22、`adminCidr` → Server Subnet、Allow |
| HTTP受信 | TCP/80、Internet → Server Subnet、`openHttp=true` の場合だけAllow |
| その他受信 | Azure既定規則でDeny |

`adminCidr` は作業場所のグローバルIPv4に `/32` を付ける。場所が変わったら再確認する。`0.0.0.0/0` は検証で拒否する。

## VM

| 項目 | 値 |
|---|---|
| OS | Ubuntu Server 24.04 LTS Gen2 |
| 既定サイズ | `Standard_B1s` |
| 認証 | SSH公開鍵のみ |
| 管理者名 | `azureadmin`（`admin`, `root` 等は禁止） |
| OS disk | StandardSSD_LRS / 30 GiB |
| Boot diagnostics | Managed storage |
| 初期構成 | cloud-initでNginxを導入・有効化 |

VMサイズとイメージが対象リージョン・サブスクリプションで利用可能か、実施直前に確認する。

```powershell
az vm list-skus --location japaneast --size Standard_B1s --all --output table
az vm image show --location japaneast --urn Canonical:ubuntu-24_04-lts:server:latest
```

## 監視

| 項目 | 値 |
|---|---|
| Log Analytics SKU | PerGB2018 |
| 保持期間 | 30日 |
| CPUアラート | 5分窓、1分ごと評価、平均80%超 |
| Severity | 2 |

> [!NOTE]
> Workspaceは作成するが、Azure Monitor AgentとData Collection Ruleは対象外である。そのためVM内のsyslogは自動収集されない。CPUアラートはLog AnalyticsではなくAzureプラットフォームメトリックを使用する。

## 依存関係

`Resource Group → VNet/NSG/Public IP/Workspace → NIC → VM → Alert`

Bicepが依存関係を解析するため、手動で作成順を覚えるより、各リソースが何を参照するかを理解する。

## 変更管理

| 変更 | 影響 | 事前確認 |
|---|---|---|
| CIDR変更 | SSH可否 | 現在の接続元IP、代替接続経路 |
| VM SKU変更 | 再起動・費用・性能 | SKU在庫、停止許容時間、料金 |
| Address Space変更 | 再構築・接続影響 | 重複、将来接続、NIC割当 |
| HTTP開放 | 攻撃面増加 | 公開の必要性、TLS/WAF要件 |
