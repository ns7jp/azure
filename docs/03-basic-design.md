# 03. 基本設計書

## 1. 設計方針

Azure Well-Architected Frameworkの5柱を、この学習案件では次のように適用する。

| 柱 | 採用内容 | 残る課題・トレードオフ |
|---|---|---|
| 信頼性 | IaCで再作成可能、起動診断 | 単一VMのため冗長性なし |
| セキュリティ | SSH鍵、CIDR制限、HTTP既定閉鎖 | Public IPを使用 |
| コスト最適化 | 小さいSKU、短期利用、削除手順 | 正確な金額は事前見積が必要 |
| 運用性 | タグ、Log Analytics、CPUアラート、Runbook | 通知先は環境ごとに追加が必要 |
| 性能効率 | SKUをパラメーター化 | 自動スケールなし |

## 2. 論理構成

- 1 Resource Groupに案件の全リソースを収容する。
- 1 VNet / 1 SubnetにサーバーNICを配置する。
- NSGはSubnetへ関連付け、入口で通信を制御する。
- VMはSSH公開鍵で管理する。
- cloud-initが初回起動時にNginxをインストールする。
- Log Analytics Workspaceを将来のログ集約先として用意する。学習版ではOSログをまだ送信しない。
- Azure MonitorのメトリックアラートでCPU高負荷を検知する。

## 3. 非機能設計

### 可用性

学習版は単一VM。RTO(目標復旧時間)は4時間、RPO(許容データ損失)は24時間を仮置きするが、バックアップが対象外のため本番要件は満たさない。

### セキュリティ

- 最小権限: 構築者に必要なAzureロールだけ付与する。
- 最小通信: SSHは管理者CIDRのみ。HTTPは明示時のみ。
- 認証: パスワードログインを無効化する。
- 秘密管理: 秘密鍵をAzureやGitへ置かない。
- 証跡: テナントID等をマスクする。
- 管理アクセス経路: Public IP直結を維持し、Azure Bastion/VPN Gatewayは本教材の規模には過剰と判断して不採用とした。比較の詳細は[ADR-002](decisions/ADR-002-bastion-vs-public-ip.md)を参照。

### 監視

CPUアラートはVMのプラットフォームメトリックを直接監視する。Log AnalyticsへOSログを送るにはAzure Monitor AgentとData Collection Ruleが別途必要であり、本案件では未構成である。

| 対象 | 方法 | しきい値 | 初動 |
|---|---|---:|---|
| VM CPU | Percentage CPU | 5分平均 80%超 | プロセスと負荷確認 |
| VM稼働 | Power state / Activity Log | 停止・割当解除 | 変更者と障害有無確認 |
| Web | curl/ブラウザー | 応答不可 | NSG→VM→Nginxの順に切り分け |

### コスト

金額を固定値で書かない。VMサイズ、OSディスク、Public IP、Log Analytics取り込み・保持、データ転送をPricing Calculatorでデプロイ当日に見積もる。

## 4. 命名・タグ

命名形式: `<種類>-<案件>-<環境>-<リージョン略称>-<連番>`

例: `vm-portfolio-dev-jpe-001`

必須タグ: `Environment`, `Project`, `Owner`, `ManagedBy`, `DataClassification`

## 5. 将来構成

本番要件が追加されたら、Public IP直結をやめ、Application Gateway/WAF、Private Endpoint/Bastion、Availability Zones、Backup、Defender for Cloud、通知付きAction Groupを検討する。Public IP直結からBastion/VPNへ切り替える判断基準は[ADR-002](decisions/ADR-002-bastion-vs-public-ip.md)の「見直し条件」を参照。
