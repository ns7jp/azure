# ADR-004: 基礎編にAzure Backup(日次・LRS)を追加する

- 状態: Accepted
- 日付: 2026-09-08
- 要件・課題: [不足点と学習ロードマップ](../09-gap-analysis-and-roadmap.md)は「高: バックアップ・復元」を挙げ、「RPO 24時間を記載しているが、現状では達成手段がない」と指摘している。Stage 4の改善候補「Backupを追加し、別名VMまたは隔離環境への復元を試験する」に対応する。
- 制約:
  - 実Azure環境への課金・認証情報を使わずに、IaC(Bicep)とドキュメントの変更として実施する。
  - README「コスト配慮」の方針(小さいVM、概算前提の明記)を踏まえ、バックアップも学習コストを抑えた構成とする。
  - 発展編(`infra/advanced/modules/backup.bicep`)がGRS・日次/週次/月次ポリシーで5台のVMを保護しており、構成の考え方を踏襲する。
- 選択肢:
  - 案A(現状維持): バックアップを構成せず、RPO 24時間を「仮置き」のまま残す。
  - 案B: Recovery Services Vaultを追加し、単一VMを日次バックアップ(30日保持)・LRS(ローカル冗長)で保護する。
  - 案C: 案Bに加えて、発展編と同様に週次・月次の長期保持ポリシーとGRS(Geo冗長)を採用する。
- 判断: 案B(日次バックアップ+LRS)を採用する。案Cは基礎編の学習コスト・ストレージ費用に対して過剰なため見送り、必要になった場合は発展編([infra/advanced/modules/backup.bicep](../../infra/advanced/modules/backup.bicep))を参考に拡張する。

## 実装内容

- `infra/modules/backup.bicep`(新規)
  - Recovery Services Vault(`rsv-<suffix>`)を作成。
  - バックアップストレージ冗長性を`LocallyRedundant`(LRS)に設定(既定のGRSより低コスト)。
  - バックアップポリシー(`bkp-<suffix>`)を作成: 毎日02:00(Tokyo Standard Time)、AzureIaasVM、30日間保持(週次・月次なし)。
  - VM(`vm-<suffix>`)をバックアップ保護対象として登録。
  - バックアップジョブ失敗時のAzure Monitor通知(`alertsForAllJobFailures`)を有効化。
- `infra/main.bicep`: `workload`モジュールの出力(`vmName`, `vmId`)を`backup`モジュールへ渡し、`recoveryVaultName`を出力に追加。
- `infra/modules/workload.bicep`: バックアップ登録に必要な`vmId`出力を追加。
- `scripts/verify.ps1`: 必須リソース一覧に`Microsoft.RecoveryServices/vaults`を追加。
- ドキュメント: `docs/03-basic-design.md`(可用性・監視)、`docs/04-detailed-design.md`(バックアップ表)、`docs/06-test-plan.md`(試験ID `BK-01`, `BK-02`)、`docs/07-operations-runbook.md`(バックアップ・復元手順)、`README.md`を更新。

## 理由

- RPO 24時間を「記載しているが達成手段がない」状態は、要件と実装が一致しておらず、ポートフォリオとして説得力を欠く。日次バックアップは最小構成でこの記載を実態と一致させられる。
- LRSはGRSよりストレージ費用が低く、README「コスト配慮」の方針と整合する。単一の学習用VMではリージョン障害まで想定した地理的保全は過剰と判断した。
- 週次・月次の長期保持(案C)は、基礎編の「未経験者が最短で理解できる」範囲を超えるため見送った。長期保持や高可用性が必要な題材は、既に発展編に実装例がある。

## 影響

- 得られる効果: バックアップジョブの実行結果を`az backup job list`で確認でき、復元試験(`BK-02`)を通じて「バックアップが取れているだけでなく、実際に復元できる」ことを証跡として残せるようになる。09-gap-analysis-and-roadmap.mdの「バックアップ・復元」項目が、設計・実装レベルでは対応済みとなる。
- 新たな欠点: バックアップストレージの課金が新たに発生する(取得したリカバリポイントの容量に応じた従量課金)。復元試験用の一時VMを削除し忘れると二重課金が続く。LRSのため、対象リージョン(japaneast)全体の障害時にはバックアップデータも失われうる。

## 検証

- 静的検証: `az bicep build --file infra/main.bicep`がエラー・警告なく完了すること(CI `.github/workflows/validate.yml`)。
- 実機検証(利用者が[Stage 3実施ランブック](10-stage3-runbook.md)で実施): 試験ID `BK-01`(初回バックアップジョブの完了確認)、`BK-02`(別名VMへの復元試験)。実施するまでは`NOT RUN`として扱う。

## 見直し条件

- 単一リージョン障害への耐性が必要になった場合(LRS→GRSへの変更)。
- 30日を超える保持期間や週次・月次の長期保持が必要になった場合(発展編の`backup.bicep`を参考に拡張)。
- 複数VM構成へ移行し、DBサーバー等でトランザクションログ単位のバックアップ(AzureWorkloadバックアップ)が必要になった場合。
