# 構築�E試験証跡

## 実施惁E��

| 頁E�� | 記録 |
|---|---|
| 案件 | Azure Portfolio Lab |
| 実施老E| ns7jp |
| 開始日晁E| 2026-09-08 16:48 JST |
| 終亁E��晁E| `YYYY-MM-DD HH:mm JST` |
| 対象環墁E| `dev` |
| Subscription | ********-****-****-****-********2945 |
| Git commit | 6d93982 |
| 変更承誁E| 自己学翁E|

## 事前確誁E

- [ ] 課金と予算アラートを確誁E
- [x] 対象サブスクリプションを確誁E
- [x] 秘寁E��報がGit差刁E��なぁE
- [ ] What-Ifに想定外�E作�E・変更・削除がなぁE
- [ ] ロールバック方法を確誁E

## What-If予想と実測

What-Ifを実行すめE**剁E* に予想を書き、実行後に実測を転記して差を記録する�E�ロード�EチE�E Stage 2 の課題）。予想の材料は `infra/main.bicep`、`infra/modules/workload.bicep`、`infra/modules/backup.bicep`、`scripts/verify.ps1`、E

| リソース種顁E| 予想した名前 | 予想個数 | What-If実測 | 一致 | 差の琁E�� |
|---|---|---|---|---|---|
| Microsoft.Resources/resourceGroups | rg-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Network/virtualNetworks | vnet-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Network/networkSecurityGroups | nsg-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Network/publicIPAddresses | pip-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Network/networkInterfaces | nic-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Compute/virtualMachines | vm-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Compute/virtualMachines/extensions | AzureMonitorLinuxAgent | 1 | | | |
| Microsoft.OperationalInsights/workspaces | log-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Insights/metricAlerts | alert-cpu-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Insights/actionGroups | ag-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Insights/dataCollectionRules | dcr-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.Insights/dataCollectionRuleAssociations | dcra-portfolio-dev-jpe-001 | 1 | | | |
| Microsoft.RecoveryServices/vaults | rsv-portfolio-dev-jpe-001 | 1 | | | |
| �E�予想に無かったもの�E�E| | | | | |

## 試験結果

試験IDと手頁E�E `docs/06-test-plan.md`、実施頁E�E `docs/10-stage3-runbook.md`。結果は `PASS` / `FAIL` / `BLOCKED` / `NOT RUN` のぁE��れかで、空欁E��残さなぁE��E

| ID | 実施日晁E| 期征E�� | 実測 | 結果 | 証跡 |
|---|---|---|---|---|---|
| ST-01 | 2026-09-08 16:48 | Bicep build成功 | 終亁E��ーチE、エラーなぁE| PASS | az bicep build --file infra/main.bicep |
| ST-02 | | What-If成功、想定リソースのみ | | NOT RUN | |
| CT-01 | | 忁E��リソース存在、SSH允E��陁E| | NOT RUN | |
| CT-02 | | 忁E��タグ付与済み | | NOT RUN | |
| NT-01 | | 許可元SSH成功 | | NOT RUN | |
| NT-02 | | 非許可元SSH失敁E| | NOT RUN | |
| NT-03 | | `openHttp=false` で外部HTTP失敁E| | NOT RUN | |
| NT-04 | | `openHttp=true` で HTTP 200�E�任意！E| | NOT RUN | |
| OS-01 | | Nginx active | | NOT RUN | |
| OS-02 | | Nginx ぁE80/tcp めEListen | | NOT RUN | |
| OS-03 | | Azure Monitor Agentが稼働中 | | NOT RUN | |
| MN-01 | | CPUアラーチE 対象VM、E0%、有効、Action Group接綁E| | NOT RUN | |
| MN-02 | | CPUアラート発火時に通知メールが到遁E| | NOT RUN | |
| MN-03 | | Log AnalyticsのPerf/SyslogがKQLで参�E可能 | | NOT RUN | |
| BK-01 | | 初回バックアチE�EジョブがCompleted | | NOT RUN | |
| BK-02 | | 隔離環墁E��の復允E��Nginx等�E動作確誁E| | NOT RUN | |
| OP-01 | | 再What-Ifで不要な置換なぁE| | NOT RUN | |
| CL-01 | | RG削除後に存在しなぁE| | NOT RUN | |

## 発生事象・対忁E

失敗、また�E意図皁E��安�Eな不一致めE**最佁E件** 記録する�E�ロード�EチE�E Stage 3 達�E条件�E�。「事象」だけでなく、仮説→確認�E修正→�E試験�E流れが�Eかるように書く、E

| 時刻 | 事象 | 立てた仮説 | 確認したこと | 修正 | 再試験�E結果 |
|---|---|---|---|---|---|
| | | | | | |

## 削除・費用確誁E

| 頁E�� | 記録 |
|---|---|
| `remove.ps1` 実行日晁E| |
| Recovery Services VaultのバックアチE�E保護解除結果 | `<remove.ps1が�E動実行。エラーが無ぁE��>` |
| `az group exists` の結果 | `<false が期征E��>` |
| Cost Management 確認日時と実績 | `<期間・金額�ERG外�E残存有無>` |
| `openHttp` めE`false` に戻したぁE| `<NT-04 実施時�Eみ>` |

## 残課顁E

- 予算アラート未設定。フェーズ3(課金開姁Eへ進む前に設定する、E- 今回の実施篁E��はフェーズ2(What-If)まで。フェーズ3、Eは NOT RUN、E- ロールバック手頁Edocs/05-build-guide.md)は未読。フェーズ3の前に確認する、E

- サブスクリプション(Azure subscription 1)の無料クレジットが期限切れで無効状態。az deployment sub what-ifが「The subscription ... is disabled and therefore marked as read only」エラーで失敗。フェーズ2(What-If)は、従量課金プランへのアップグレードまたは新規無料アカウント発行でサブスクリプションを有効化した後に再開する。
