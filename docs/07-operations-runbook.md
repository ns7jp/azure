# 07. 運用・障害対応Runbook

## 毎日の確認

1. Azure Service Healthに影響がないか。
2. Azure Monitorアラートが発生していないか。
3. VMのPower Stateは想定どおりか。
4. Web応答と直近変更は正常か。

## 毎月の確認

- Cost Managementで予算差異と不要リソースを確認。
- Defender for Cloud / Advisorの推奨事項を評価。
- OS更新、容量、ログ量、アカウント・RBACを確認。
- Recovery Services Vaultのバックアップジョブ履歴を確認し、失敗が続いていないか確認。
- 復旧手順を机上または隔離環境で訓練。

## インシデント初動：止・見・守・戻・残

1. **止** — 影響拡大を止める。無計画な再起動をしない。
2. **見** — 時刻、症状、範囲、直前変更、アラートを見る。
3. **守** — ログと証跡を保全。秘密情報は記録しない。
4. **戻** — 承認済み手順で復旧し、動作を再確認する。
5. **残** — 原因、対応、再発防止、タイムラインを残す。

## Webに接続できない

```powershell
az vm get-instance-view -g rg-portfolio-dev-jpe-001 -n vm-portfolio-dev-jpe-001 --query instanceView.statuses -o table
az network nsg rule list -g rg-portfolio-dev-jpe-001 --nsg-name nsg-portfolio-dev-jpe-001 -o table
az network public-ip show -g rg-portfolio-dev-jpe-001 -n pip-portfolio-dev-jpe-001 -o table
```

VM内:

```bash
sudo systemctl status nginx
sudo nginx -t
curl -v http://127.0.0.1/
sudo ss -lntp
sudo journalctl -u nginx --since "1 hour ago" --no-pager
```

判断:

- localhostも失敗: Nginx設定・サービス・OSを調べる。
- localhost成功、外部失敗: NSG、Public IP、NIC、経路を調べる。
- 一部利用者だけ失敗: 接続元IP、プロキシ、DNS、端末側を調べる。

## SSHできない

1. 自分の現在のグローバルIPと `adminCidr` を比較。
2. NSGの22/tcpと優先度を確認。
3. VMがRunningか確認。
4. 使用中のユーザー名・秘密鍵・鍵権限を確認。
5. Azure Serial Console等の代替経路は、権限と監査方針を確認して利用。

秘密鍵をチャット、Issue、証跡へ貼らない。

## CPU高騰

```bash
uptime
top -b -n 1 | head -30
ps aux --sort=-%cpu | head
journalctl --since "30 minutes ago" --no-pager | tail -200
```

プロセスを即時終了する前に、業務影響と原因調査に必要な情報を保存する。再起動は復旧になっても原因除去にならない。

## バックアップ・復元

Recovery Services Vault(`rsv-<suffix>`)が毎日02:00(JST)にVM全体をバックアップし、30日間保持する。設計判断は[ADR-004](decisions/ADR-004-backup-policy.md)を参照。

### バックアップ状況の確認

```powershell
az backup job list --resource-group rg-portfolio-dev-jpe-001 --vault-name rsv-portfolio-dev-jpe-001 --output table
az backup item list --resource-group rg-portfolio-dev-jpe-001 --vault-name rsv-portfolio-dev-jpe-001 --output table
```

### 復元(隔離環境への別名復元)

本番相当のVMを直接上書きせず、必ず別名(例: `vm-restore-test`)の新規VMへ復元してから内容を確認する。

1. 復元ポイントを確認する。

   ```powershell
   az backup recoverypoint list `
     --resource-group rg-portfolio-dev-jpe-001 `
     --vault-name rsv-portfolio-dev-jpe-001 `
     --container-name vm-portfolio-dev-jpe-001 `
     --item-name vm-portfolio-dev-jpe-001 `
     --output table
   ```

2. 選んだ復元ポイントから、別名の新規VMとして復元する(`--restore-to-staging-storage-account`または`az backup restore restore-disks`を用いる。詳細はAzure Backupの公式手順を参照)。
3. 復元されたVMにSSH接続し、`OS-01`/`OS-02`相当の確認(Nginx稼働、80/tcp Listen)を行う。
4. 確認後、復元用に作成したリソース(VM、ディスク、NIC等)をすべて削除し、二重課金を避ける。
5. 実施結果を試験ID `BK-01`(バックアップジョブ確認)・`BK-02`(復元試験)として、日時・実施者・合否とともに証跡に残す。

### よくある失敗

- 初回バックアップが完了する前に復元を試みる: バックアップジョブが`Completed`になるまで数時間待つ。
- 復元VMを元のVM名やNSG/Public IPと衝突する名前で作成してしまう: 必ず一意な別名を使う。
- 復元検証後にリソースを削除し忘れる: バックアップ由来のディスク・VMは通常のリソースと同様に課金され続ける。

## 変更手順

1. Issueへ目的・影響・ロールバック・試験を書く。
2. ブランチでBicepまたは文書を変更。
3. lint、build、What-If、レビュー。
4. 承認後に適用。
5. 試験と監視確認。
6. 証跡、結果、残課題を記録。

## エスカレーション情報

- 発生・検知時刻（タイムゾーン含む）
- 影響を受ける利用者・機能
- 正常だった最終時刻
- 直前の変更
- 実施した確認と結果
- 現在の暫定対応
- 関連するアラート、Activity Log、Correlation ID（秘密は除く）
