# 構築・試験証跡

## 実施情報

| 項目 | 記録 |
|---|---|
| 案件 | Azure Portfolio Lab |
| 実施者 | `<GitHub名等>` |
| 開始日時 | `YYYY-MM-DD HH:mm JST` |
| 終了日時 | `YYYY-MM-DD HH:mm JST` |
| 対象環境 | `dev` |
| Subscription | `<末尾4桁以外をマスク>` |
| Git commit | `<commit SHA>` |
| 変更承認 | `<Issue/PR URL または自己学習>` |

## 事前確認

- [ ] 課金と予算アラートを確認
- [ ] 対象サブスクリプションを確認
- [ ] 秘密情報がGit差分にない
- [ ] What-Ifに想定外の作成・変更・削除がない
- [ ] ロールバック方法を確認

## What-If予想と実測

What-Ifを実行する **前** に予想を書き、実行後に実測を転記して差を記録する（ロードマップ Stage 2 の課題）。予想の材料は `infra/main.bicep`、`infra/modules/workload.bicep`、`scripts/verify.ps1`。

| リソース種類 | 予想した名前 | 予想個数 | What-If実測 | 一致 | 差の理由 |
|---|---|---|---|---|---|
| Microsoft.Resources/resourceGroups | | | | | |
| Microsoft.Network/virtualNetworks | | | | | |
| Microsoft.Network/networkSecurityGroups | | | | | |
| Microsoft.Network/publicIPAddresses | | | | | |
| Microsoft.Network/networkInterfaces | | | | | |
| Microsoft.Compute/virtualMachines | | | | | |
| Microsoft.OperationalInsights/workspaces | | | | | |
| Microsoft.Insights/metricAlerts | | | | | |
| （予想に無かったもの） | | | | | |

## 試験結果

試験IDと手順は `docs/06-test-plan.md`、実施順は `docs/10-stage3-runbook.md`。結果は `PASS` / `FAIL` / `BLOCKED` / `NOT RUN` のいずれかで、空欄を残さない。

| ID | 実施日時 | 期待値 | 実測 | 結果 | 証跡 |
|---|---|---|---|---|---|
| ST-01 | | Bicep build成功 | | NOT RUN | |
| ST-02 | | What-If成功、想定リソースのみ | | NOT RUN | |
| CT-01 | | 必須リソース存在、SSH元制限 | | NOT RUN | |
| CT-02 | | 必須タグ付与済み | | NOT RUN | |
| NT-01 | | 許可元SSH成功 | | NOT RUN | |
| NT-02 | | 非許可元SSH失敗 | | NOT RUN | |
| NT-03 | | `openHttp=false` で外部HTTP失敗 | | NOT RUN | |
| NT-04 | | `openHttp=true` で HTTP 200（任意） | | NOT RUN | |
| OS-01 | | Nginx active | | NOT RUN | |
| OS-02 | | Nginx が 80/tcp を Listen | | NOT RUN | |
| MN-01 | | CPUアラート: 対象VM、80%、有効 | | NOT RUN | |
| OP-01 | | 再What-Ifで不要な置換なし | | NOT RUN | |
| CL-01 | | RG削除後に存在しない | | NOT RUN | |

## 発生事象・対応

失敗、または意図的な安全な不一致を **最低1件** 記録する（ロードマップ Stage 3 達成条件）。「事象」だけでなく、仮説→確認→修正→再試験の流れが分かるように書く。

| 時刻 | 事象 | 立てた仮説 | 確認したこと | 修正 | 再試験の結果 |
|---|---|---|---|---|---|
| | | | | | |

## 削除・費用確認

| 項目 | 記録 |
|---|---|
| `remove.ps1` 実行日時 | |
| `az group exists` の結果 | `<false が期待値>` |
| Cost Management 確認日時と実績 | `<期間・金額・RG外の残存有無>` |
| `openHttp` を `false` に戻したか | `<NT-04 実施時のみ>` |

## 残課題

- `<未実施、制約、次回改善を記録>`
