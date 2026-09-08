# ADR-003: 基礎編にAction Group通知とAMA/DCRによるOSログ収集を追加する

- 状態: Accepted
- 日付: 2026-09-08
- 要件・課題: [不足点と学習ロードマップ](../09-gap-analysis-and-roadmap.md)は「高: 監視通知とOSログ収集」を挙げ、基礎編が「CPUアラートの定義と空のWorkspaceだけで、担当者への通知やsyslog調査ができない」状態にあると指摘している。Stage 4の改善候補「Action GroupとOSログ収集を追加し、通知とKQL検索を試験する」に対応する。
- 制約:
  - 実Azure環境への課金・認証情報を使わずに、IaC(Bicep)とドキュメントの変更として実施する。
  - `openHttp`既定false・SSHの`adminCidr`限定など既存の安全設定は変更しない。
  - 発展編(`infra/advanced/modules/monitoring.bicep`)がWindows VM向けにAMA/DCR/Action Groupをすでに実装しており、構成の考え方を踏襲する。
- 選択肢:
  - 案A(現状維持): CPUアラートは定義のみとし、Log Analytics Workspaceは空のまま将来課題として残す。
  - 案B: Action Group(メール通知)をCPUアラートに接続し、Azure Monitor Agent for Linux(AMA)とData Collection Rule(DCR)でCPU/ディスク空き容量のパフォーマンスカウンターとsyslogをLog Analyticsへ送信する。
  - 案C: 案Bに加えて、ディスク空き容量やHeartbeat欠落など複数のクエリアラートを追加する(発展編相当のアラート一式)。
- 判断: 案B(Action Group + AMA/DCRによるPerf・Syslog収集)を採用する。案Cは基礎編の学習範囲を超えるため見送り、必要になった場合は発展編([infra/advanced/modules/monitoring.bicep](../../infra/advanced/modules/monitoring.bicep))を参照する形とする。

## 実装内容

- `infra/main.bicep` / `infra/modules/workload.bicep`
  - `alertEmailAddress`パラメーターを追加し、Action Group(`ag-<suffix>`)のメール受信者に設定。
  - CPUメトリックアラート(`alert-cpu-<suffix>`)の`actions`にAction Groupを接続。
  - Data Collection Rule(`dcr-<suffix>`)を追加し、パフォーマンスカウンター(`% Processor Time`, `% Free Space`)を60秒間隔、syslog(`auth`/`authpriv`/`daemon`/`syslog`のWarning以上)をLog Analyticsへ送信。
  - VMに`AzureMonitorLinuxAgent`拡張機能を追加し、Data Collection Rule Associationで関連付け。
- `infra/parameters/dev.example.bicepparam`: `alertEmailAddress`の例をプレースホルダー付きで追加。
- `scripts/deploy.ps1`: `alertEmailAddress`がプレースホルダーのままの場合にWhat-If前で停止するチェックを追加(既存の公開鍵プレースホルダー検査と同じパターン)。
- `scripts/verify.ps1`: 必須リソース一覧にAction Group、Data Collection Rule、Data Collection Rule Association、VM拡張機能を追加。
- ドキュメント: `docs/03-basic-design.md`、`docs/04-detailed-design.md`、`docs/06-test-plan.md`(試験ID `OS-03`, `MN-02`, `MN-03`を追加)、`README.md`を更新。

## 理由

- Action Group未接続のCPUアラートは「検知はするが誰にも届かない」状態であり、運用としての価値が低い。メール通知への接続は追加コストがほぼ発生せず、最小の変更で解消できる。
- README/09-gap-analysis-and-roadmap.mdで明示的に「OSログ収集は発展課題」とされてきた欠落を、発展編で実績のあるAMA/DCRパターンを流用することで解消できる。
- syslogのみに絞り、ディスク低下・Heartbeat欠落等の追加アラート(案C)は見送ることで、基礎編の学習コストを「未経験者が最短で理解できる」範囲に保つ(README「学習教材としての適合性」の方針と整合)。

## 影響

- 得られる効果: CPUアラートが実際に人へ届く経路を持ち、Log AnalyticsのPerf/SyslogテーブルにKQLで問い合わせられるようになる。09-gap-analysis-and-roadmap.mdの要件トレーサビリティ表`NFR-02`(監視)の実装記述がより実態に近くなる。
- 新たな欠点: Log Analyticsの取り込み量がわずかに増える(Perf 60秒間隔+syslog)。AMA拡張機能のインストールに失敗した場合、VMの初回起動時間や試験手順(`OS-03`)に影響しうる。`alertEmailAddress`という新しいパラメーターが増え、`dev.bicepparam`作成時に設定が必須になる。

## 検証

- 静的検証: `az bicep build --file infra/main.bicep`がエラー・警告なく完了すること(CI `.github/workflows/validate.yml`)。
- 実機検証(利用者が[Stage 3実施ランブック](10-stage3-runbook.md)で実施): 試験ID `MN-02`(Action Group宛のメール到達)、`MN-03`(Perf/SyslogテーブルへのKQLクエリ)、`OS-03`(AMAサービスの稼働確認)。実施するまでは`NOT RUN`として扱う。

## 見直し条件

- ディスク空き容量低下やVM無応答など、CPU以外の異常もメール通知したいという要件が生じた場合(その場合は案Cまたは発展編の`monitoring.bicep`を参考に拡張する)。
- Teams/ITSM等、メール以外の通知チャネルが必要になった場合。
- Log Analyticsの取り込みコストが学習予算を圧迫する場合(収集対象や保持期間の見直し)。
