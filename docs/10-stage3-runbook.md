# 10. Stage 3 実施ランブック（基礎編・課金あり）

[不足点と学習ロードマップ](09-gap-analysis-and-roadmap.md)の Stage 3「構築して試す」を、**1回の作業セッション**として通しで実施するための手順書である。構築手順（[05](05-build-guide.md)）と試験仕様（[06](06-test-plan.md)）の内容を、実施順・証跡の残し方・安全上の注意とともに一本に束ねている。個々のコマンドの意味は05・06を参照すること。

> [!IMPORTANT]
> このセッションは **Azureの課金が発生する**。`-Apply` を付けた時点でリソースが作成され、フェーズ8で削除するまで課金が続く。開始前に予算アラートと削除手順を確認し、途中で中断する場合も必ずフェーズ8まで戻ること。

## 所要時間と費用の目安

| 項目 | 目安 |
|---|---|
| 所要時間 | 3〜5時間（ロードマップの見積り。初回は長めに見る）。バックアップの初回ジョブ完了まで数時間かかるため、BK-01/BK-02を含める場合は別セッションに分けてもよい |
| 稼働させるリソース | `Standard_B1s` VM 1台、Public IP、OSディスク、Log Analytics(Perf/Syslog収集あり)、Action Group、Recovery Services Vault(日次バックアップ) |
| 費用感 | 数時間の稼働なら小額に収まる構成だが、料金はリージョン・契約・時期で変わる。**実施直前に Azure Pricing Calculator で確認**し、実績は終了後に Cost Management で見る |

費用を増やす主な要因は「削除し忘れ」である。VMの停止だけではPublic IPやディスクの課金が残る（05「構築後の安全化」）。バックアップを有効化しているため、Recovery Services Vaultにデータが残っていると通常のRG削除が失敗することがある（フェーズ8参照、`scripts/remove.ps1`が対応済み）。

## 事前に用意するもの

- PowerShell 7、Azure CLI、Bicep CLI、SSHクライアント（05 フェーズA）
- 学習用サブスクリプションと、そこにリソースを作成できる権限
- SSH鍵ペア（無ければ05の `ssh-keygen` で作成。**秘密鍵は絶対にリポジトリへ入れない**）
- 現在の自分のグローバルIPv4アドレス（`adminCidr` に `/32` で使う）
- CPUアラート・バックアップジョブ失敗通知を受け取るメールアドレス（`alertEmailAddress`）
- `evidence/deployment-record.example.md` のコピー（このセッションの証跡ファイル）

```powershell
Copy-Item evidence/deployment-record.example.md evidence/deployment-record-YYYYMMDD.md
```

以降、「証跡へ記録」とはこのコピーに書くことを指す。記録ルールは06「記録ルール」と `evidence/README.md` に従う（秘密情報・未マスクのIDは書かない、未実施は `NOT RUN`）。

## 実施フロー全体像

```text
フェーズ0 準備・安全確認
フェーズ1 静的検証と予想 ─── ST-01
フェーズ2 What-If と差分 ─── ST-02   ← ここまで課金なし
フェーズ3 構築 ──────────── （デプロイ記録）      ← ここから課金開始
フェーズ4 構成確認 ──────── CT-01, CT-02, MN-01
フェーズ5 接続・OS・監視試験 ─ NT-01, OS-01, OS-02, OS-03, MN-02, MN-03, NT-03, (NT-04), NT-02
フェーズ6 再現性と失敗記録 ─ OP-01 + 意図的な不一致1件
フェーズ7 バックアップ確認・復元試験(任意) ─ BK-01, BK-02
フェーズ8 削除と残存確認 ── CL-01                ← ここで課金停止
フェーズ9 証跡の仕上げとコミット
```

---

## フェーズ0: 準備・安全確認

```powershell
az login
az account show --output table
git rev-parse --short HEAD
```

証跡へ記録: 実施者、開始日時、対象サブスクリプション（末尾4桁以外をマスク）、Git commit SHA。「事前確認」チェックリストを埋める。

パラメーターファイルを用意する（05 フェーズB）。

```powershell
Copy-Item infra/parameters/dev.example.bicepparam infra/parameters/dev.bicepparam
# 編集: owner, sshPublicKey(.pubの1行), adminCidr(自分のIP/32), openHttp=false, alertEmailAddress(通知用メール)
git status --short   # dev.bicepparam が表示されない(.gitignore対象)ことを確認
```

`sshPublicKey` に `REPLACE_WITH_YOUR_PUBLIC_KEY` が残っている、`alertEmailAddress` に `REPLACE_WITH_YOUR_ALERT_EMAIL` が残っている、`adminCidr` が `0.0.0.0/0` である、秘密鍵を貼っている、のいずれかがあると `deploy.ps1` は停止する。これは想定された安全装置なので、止まったら値を直す。

## フェーズ1: 静的検証と予想（ST-01）

```powershell
az bicep build --file infra/main.bicep
```

終了コード0を **ST-01** として記録する。

次に、**What-Ifを実行する前に**「作成されるリソースの種類・名前・個数」を予想し、証跡の「What-If予想と実測」表に書く。予想の材料は `infra/main.bicep`（リソースグループと命名規則 `<projectName>-<environment>-<regionCode>-001`）、`infra/modules/workload.bicep`、`infra/modules/backup.bicep`、`scripts/verify.ps1` の `$requiredTypes`（現在12種類）である。答えを先に見ず、自分の読解で埋めること。この予想がStage 3の「理解して作っている」ことの証拠になる。

## フェーズ2: What-If と差分（ST-02）— 課金なし

```powershell
./scripts/deploy.ps1 -ParameterFile infra/parameters/dev.bicepparam
```

`-Apply` を付けない限りリソースは作られない。出力を読み、05 フェーズCの確認点（`Delete` が無い、RG名・リージョン・名前が設計どおり、SSH許可元が自分の `/32`、想定外のSKUが無い）を確認する。

証跡へ記録:

- **ST-02**: What-Ifが成功し、想定リソースのみ表示されたか。
- 予想表の「実測」列にWhat-Ifの結果を転記し、予想との差を **リソース単位で** 書く。差があった場合、なぜ予想が外れたかを一言残す（例: Bicepの暗黙リソースを見落とした）。

ここで想定外の内容があれば、**フェーズ3へ進まず**パラメーターやBicepを見直す。

## フェーズ3: 構築 — ここから課金開始

課金・対象サブスクリプション・削除方法（フェーズ8）を再確認してから実行する。

```powershell
./scripts/deploy.ps1 -ParameterFile infra/parameters/dev.bicepparam -Apply
```

証跡へ記録: 実行日時、終了コード、出力の要点（`resourceGroupName`、`vmName`、`publicIpAddress`、`recoveryVaultName`。サブスクリプションIDやテナントIDはマスク）。

失敗した場合はむやみに再実行せず、05「ロールバック」の手順で失敗箇所を確認し、証跡の「発生事象・対応」に残す。

## フェーズ4: 構成確認（CT-01, CT-02, MN-01）

```powershell
./scripts/verify.ps1 -ResourceGroupName rg-portfolio-dev-jpe-001
```

**CT-01**: 必須12種のリソースがすべて `PASS`、かつ「SSH source is restricted」が `PASS`。

```powershell
az resource list --resource-group rg-portfolio-dev-jpe-001 --query "[].{name:name,type:type,tags:tags}" --output json
```

**CT-02**: 各リソースに `Environment` / `Project` / `Owner` / `ManagedBy` / `DataClassification` のタグが付いているか。

```powershell
az monitor metrics alert list --resource-group rg-portfolio-dev-jpe-001 --output table
az monitor metrics alert show --resource-group rg-portfolio-dev-jpe-001 --name <上で表示された名前> --query "{enabled:enabled,scopes:scopes,criteria:criteria,actions:actions}" --output json
```

**MN-01**: 対象がこのVM、しきい値80%、`enabled: true`、かつ`actions`にAction Groupが設定されていること。

```powershell
az vm get-instance-view --resource-group rg-portfolio-dev-jpe-001 --name vm-portfolio-dev-jpe-001 --query instanceView.statuses --output table
```

`PowerState/running` を確認してからフェーズ5へ進む。

## フェーズ5: 接続・OS・監視試験（NT-01, OS-01, OS-02, OS-03, MN-02, MN-03, NT-03, NT-04, NT-02）

### NT-01: 許可元からのSSH

```powershell
$ip = az network public-ip show --resource-group rg-portfolio-dev-jpe-001 --name pip-portfolio-dev-jpe-001 --query ipAddress --output tsv
ssh -i "$env:USERPROFILE/.ssh/azure_portfolio" azureadmin@$ip
```

公開鍵で接続できれば **NT-01** PASS。パスワードを聞かれる場合は鍵の指定を確認する（パスワード認証は無効化されている）。

### OS-01, OS-02, OS-03: VM内の確認（SSHセッション内で実行）

```bash
hostnamectl
systemctl is-active nginx                          # OS-01: active
ss -lntp                                            # OS-02: nginx が 0.0.0.0:80 を LISTEN
curl --fail http://127.0.0.1/                       # ローカルからは応答する
systemctl status azuremonitoragent --no-pager       # OS-03: active (running)
exit
```

AMA(Azure Monitor Agent)は初回起動から数分かかることがある。`inactive`の場合は数分待って再確認する。06「VM内確認コマンド」の残り（`df -h`、`free -m`、`journalctl -u nginx`）も実行して要点を記録しておくと、後の運用・障害対応の練習になる。

### MN-02: Action Group通知の到達確認

CPUアラートが実際にメールへ届くかを確認する。安全に負荷をかける方法として、隔離学習環境で短時間だけCPUを高負荷にする。

```bash
sudo apt-get update && sudo apt-get install -y stress-ng
stress-ng --cpu 1 --timeout 360s
```

5分平均CPUが80%を超えた状態が続くと、数分以内にアラートが発火し、`alertEmailAddress`宛にメールが届く。届いたら **MN-02** PASS、届かない場合はAction Groupの受信者設定と評価状況(`az monitor metrics alert show`)を確認する。

### MN-03: Perf/SyslogのKQLクエリ確認

Azure Portal → Log Analytics ワークスペース(`log-portfolio-dev-jpe-001`) → ログ で以下を実行する。

```kusto
Perf
| where Computer contains "vm-"
| take 10
```

```kusto
Syslog
| take 10
```

いずれも直近収集分のレコードが返れば **MN-03** PASS。AMAインストール直後は数分〜十数分のタイムラグがあるため、結果が0件の場合は少し待って再実行する。

### NT-03: HTTP閉鎖（`openHttp=false` のまま）

```powershell
curl.exe --max-time 10 "http://$ip"
```

外部からは **接続失敗**（タイムアウト）が期待値。「VM内では応答するが外からは届かない」= NSGが機能している、という理解を証跡に一言書く。

### NT-04（任意）: HTTP開放の確認

`dev.bicepparam` の `openHttp` を `true` にし、フェーズ2→3と同様にWhat-If→`-Apply` で再デプロイする。What-Ifで **NSG規則の追加だけ** が差分として出ることを確認する。

```powershell
curl.exe --fail --max-time 10 "http://$ip"
```

HTTP 200 で **NT-04** PASS。確認後は **必ず `openHttp=false` に戻して再デプロイ** し、NT-03を再確認する（05「構築後の安全化」）。戻し忘れは証跡上も減点になる。

### NT-02: 非許可元からのSSH — 締め出し防止

06「異常系の安全な試験」のとおり、**自分を締め出さない**手順で行う。

1. 現在のSSHセッションは **開いたまま** にする（切らない）。
2. スマートフォンのテザリングなど、別のグローバルIPからSSHを試みる → 接続失敗が期待値（**NT-02** PASS）。
3. 別回線が用意できない場合は `NOT RUN` または `BLOCKED` と正直に書く。`adminCidr` を書き換えて自分を締め出す方法は、戻せなくなる恐れがあるため推奨しない。

## フェーズ6: 再現性と失敗記録（OP-01 + 意図的な不一致1件）

### OP-01: 同一Bicepの再デプロイ

```powershell
./scripts/deploy.ps1 -ParameterFile infra/parameters/dev.bicepparam
```

パラメーターを変えずにWhat-Ifを再実行し、**不要な置換（Delete/Create）が出ない**ことを確認する。`NoChange` または軽微な `Modify` のみなら PASS。差分が出た場合はその内容を記録する（これ自体が学びになる）。

### 意図的な安全な不一致を1件、仮説→確認→修正→再試験で記録する

ロードマップ Stage 3 の達成条件「少なくとも1件、起きた失敗または意図的な安全な不一致を記録」に対応する。実際に失敗が起きていればそれを使う。起きていなければ、次のような **安全な** ものを1つ選ぶ。

- `adminCidr` を一時的に `0.0.0.0/0` にして `deploy.ps1` を実行し、安全装置で **止まる** ことを確認してから元に戻す（What-Ifにも到達しないので無害）。
- `sshPublicKey` の値を1文字欠けさせてWhat-Ifを実行し、どこで・どんなエラーになるかを見てから戻す。
- `alertEmailAddress` をプレースホルダーのままにして `deploy.ps1` を実行し、安全装置で止まることを確認してから元に戻す。

証跡の「発生事象・対応」に、**事象 → 立てた仮説 → 確認したこと → 修正 → 再試験の結果** の順で書く。「何が起きたか」だけでなく「なぜそう判断したか」が面接で問われる部分である。

## フェーズ7: バックアップ確認・復元試験（BK-01, BK-02）— 任意・時間がかかる

初回バックアップジョブは、スケジュール(毎日02:00 JST)を待つか、オンデマンドで即時実行できる。時間に余裕がなければこのフェーズは別セッションに分け、証跡には `NOT RUN` と理由を書く。

### BK-01: バックアップジョブの確認

```powershell
az backup protection backup-now `
  --resource-group rg-portfolio-dev-jpe-001 `
  --vault-name rsv-portfolio-dev-jpe-001 `
  --container-name vm-portfolio-dev-jpe-001 `
  --item-name vm-portfolio-dev-jpe-001 `
  --backup-management-type AzureIaasVM `
  --backup-type Full

az backup job list --resource-group rg-portfolio-dev-jpe-001 --vault-name rsv-portfolio-dev-jpe-001 --output table
```

ジョブが `Completed` になれば **BK-01** PASS。数十分〜数時間かかることがある。

### BK-02: 隔離環境への復元試験

07「バックアップ・復元」の手順に沿って、**別名(例: `vm-restore-test`)の新規VM**へ復元する。元のVMやネットワーク設定を上書きしないこと。

1. 復元ポイントを確認する。

   ```powershell
   az backup recoverypoint list `
     --resource-group rg-portfolio-dev-jpe-001 `
     --vault-name rsv-portfolio-dev-jpe-001 `
     --container-name vm-portfolio-dev-jpe-001 `
     --item-name vm-portfolio-dev-jpe-001 `
     --output table
   ```

2. Azure Portalまたは`az backup restore restore-disks`で別名VMとして復元する。
3. 復元されたVMへSSH接続し、`OS-01`/`OS-02`相当(Nginx稼働、80/tcp Listen)を確認する。
4. 確認後、復元用に作成したリソース(VM、ディスク、NIC等)をすべて削除し、二重課金を避ける。

復元VMが正常に起動し元VMへ影響がなければ **BK-02** PASS。証跡へ、復元に使った復元ポイントの日時と、確認した内容を記録する。

## フェーズ8: 削除と残存確認（CL-01）— ここで課金停止

```powershell
./scripts/remove.ps1 `
  -ResourceGroupName rg-portfolio-dev-jpe-001 `
  -ConfirmResourceGroupName rg-portfolio-dev-jpe-001
az group exists --name rg-portfolio-dev-jpe-001     # false が期待値
```

`remove.ps1` は、RGを削除する前にRecovery Services Vault内の保護アイテムをすべて`stop-protection`(バックアップデータ削除込み)してから削除する。この操作は取消不能なので、BK-02で使った復元用リソースが残っていないか先に確認しておく。

**CL-01**: RGが存在しない。加えて、Azure Portal の Cost Management で当該期間の実績を確認し、RG外に残った課金リソースが無いことを見る。証跡へ終了日時とあわせて記録する。

## フェーズ9: 証跡の仕上げとコミット

1. 試験結果表の全行が `PASS` / `FAIL` / `BLOCKED` / `NOT RUN` のいずれかで埋まっている（空欄を残さない）。
2. `FAIL` には原因・暫定対応・再試験予定、`BLOCKED` / `NOT RUN` には理由がある。
3. 秘密鍵、パスワード、未マスクのサブスクリプション/テナントIDが **含まれていない**。
4. [09](09-gap-analysis-and-roadmap.md) の「要件トレーサビリティ表」を証跡ファイルへコピーし、`実装` と `試験結果` を今回の実体（ファイル行・リソース名・証跡の行）へ置き換える。

```powershell
git add evidence/deployment-record-YYYYMMDD.md
git diff --cached          # 秘密情報が無いことを目視
git commit -m "docs: add Stage 3 evidence (YYYY-MM-DD)"
```

## 完了判定

- [ ] 構築、SSH、HTTP閉鎖、Nginx、アラート定義、削除の証跡がある（ロードマップ Stage 3 達成条件）
- [ ] NT-02 は安全な方法で行った、または `NOT RUN` / `BLOCKED` と明記した
- [ ] What-If の予想と実測の差を、リソース単位で説明できる
- [ ] 失敗または意図的な不一致を1件、仮説→確認→修正→再試験で記録した
- [ ] MN-02(通知到達)・MN-03(KQLクエリ)・OS-03(AMA稼働)を実施したか、実施しない理由を記録した
- [ ] BK-01(バックアップジョブ)・BK-02(復元試験)を実施したか、`NOT RUN`とその理由を記録した
- [ ] RGが削除され、Cost Management で残存課金が無いことを確認した
- [ ] `openHttp` を `false` に戻した状態で終えた（NT-04 を実施した場合）

ここまで終えたら、[09](09-gap-analysis-and-roadmap.md) の「Stage 4: 1つだけ改善する」に進み、改善を **1つだけ** 選ぶ。
