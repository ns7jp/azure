# 03. 基本設計書

## 1. 設計方針

Azure Well-Architected Frameworkの5柱を、この学習案件では次のように適用する。

| 柱 | 採用内容 | 残る課題・トレードオフ |
|---|---|---|
| 信頼性 | IaCで再作成可能、起動診断、日次バックアップ | 単一VMのため冗長性なし |
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
- Log Analytics WorkspaceへAzure Monitor Agent(AMA)経由でCPU/ディスク空き容量のパフォーマンスカウンターとsyslogを送信する。
- Azure MonitorのメトリックアラートでCPU高負荷を検知し、Action Group経由でメール通知する。
- Recovery Services VaultでVM全体を日次バックアップする。

## 3. 非機能設計

### 可用性

学習版は単一VM。Recovery Services Vault(`bkp-<suffix>`ポリシー)により毎日02:00(JST)にVM全体のバックアップを取得し30日間保持することで、RTO(目標復旧時間)4時間、RPO(許容データ損失)24時間という仮置き値をIaCとしては満たす設計にした。実際のバックアップジョブ完了・復元試験は利用者が実施するまで未検証である。採用理由と復元手順は[ADR-004](decisions/ADR-004-backup-policy.md)を参照。

### セキュリティ

- 最小権限: 構築者に必要なAzureロールだけ付与する。
- 最小通信: SSHは管理者CIDRのみ。HTTPは明示時のみ。
- 認証: パスワードログインを無効化する。
- 秘密管理: 秘密鍵をAzureやGitへ置かない。
- 証跡: テナントID等をマスクする。
- 管理アクセス経路: Public IP直結を維持し、Azure Bastion/VPN Gatewayは本教材の規模には過剰と判断して不採用とした。比較の詳細は[ADR-002](decisions/ADR-002-bastion-vs-public-ip.md)を参照。

### 監視

CPUアラートはVMのプラットフォームメトリックを直接監視し、Action Group(メール通知)へ連携する。あわせてAzure Monitor Agent(AMA)とData Collection Rule(DCR)により、CPU/ディスク空き容量のパフォーマンスカウンターと`auth`/`authpriv`/`daemon`/`syslog`のsyslog(Warning以上)をLog Analyticsへ送信する。採用理由と実機検証(通知到達・KQLクエリ)の進め方は[ADR-003](decisions/ADR-003-action-group-and-os-log-collection.md)を参照。

| 対象 | 方法 | しきい値 | 初動 |
|---|---|---:|---|
| VM CPU | Percentage CPU (メトリックアラート→Action Group) | 5分平均 80%超 | プロセスと負荷確認、受信メールを確認 |
| VM稼働 | Power state / Activity Log | 停止・割当解除 | 変更者と障害有無確認 |
| Web | curl/ブラウザー | 応答不可 | NSG→VM→Nginxの順に切り分け |
| OSログ(syslog) | Log AnalyticsのSyslogテーブルをKQLで検索 | Warning以上 | 該当ログの内容とタイミングを確認 |
| バックアップジョブ | Recovery Services Vaultのバックアップジョブ一覧 | 失敗 | Azure Monitor通知内容とジョブログを確認 |

### コスト

金額を固定値で書かない。VMサイズ、OSディスク、Public IP、Log Analytics取り込み・保持、バックアップストレージ(LRS)、データ転送をPricing Calculatorでデプロイ当日に見積もる。

## 4. 命名・タグ

命名形式: `<種類>-<案件>-<環境>-<リージョン略称>-<連番>`

例: `vm-portfolio-dev-jpe-001`

必須タグ: `Environment`, `Project`, `Owner`, `ManagedBy`, `DataClassification`

## 5. 将来構成

本番要件が追加されたら、Public IP直結をやめ、Application Gateway/WAF、Private Endpoint/Bastion、Availability Zones、Defender for Cloud、Action Groupの通知先拡充(Teams/ITSM連携)、バックアップのGRS化・週次/月次保持を検討する。Public IP直結からBastion/VPNへ切り替える判断基準は[ADR-002](decisions/ADR-002-bastion-vs-public-ip.md)の「見直し条件」を、バックアップ強化の判断基準は[ADR-004](decisions/ADR-004-backup-policy.md)の「見直し条件」を参照。
