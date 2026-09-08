# 06. 試験仕様書

## 記録ルール

各試験に「日時、実施者、対象、期待値、実測、合否、証跡、備考」を残す。未実施を成功扱いせず `NOT RUN` と書く。

## 試験項目

| ID | 分類 | 手順 | 期待結果 |
|---|---|---|---|
| ST-01 | 静的 | `az bicep build --file infra/main.bicep` | エラー0 |
| ST-02 | 変更予測 | `deploy.ps1`(`-Apply`なし) | 想定リソースのみ表示 |
| CT-01 | 構成 | `verify.ps1` | 必須リソースが存在 |
| CT-02 | タグ | RG配下を一覧化 | 必須タグが付与済み |
| NT-01 | SSH正常 | 許可CIDRからSSH | 公開鍵で接続成功 |
| NT-02 | SSH異常 | 非許可CIDRからSSH | 接続失敗 |
| NT-03 | HTTP閉鎖 | `openHttp=false`でcurl | 外部から接続失敗 |
| NT-04 | HTTP正常 | `openHttp=true`でcurl | HTTP 200 |
| OS-01 | OS | `systemctl is-active nginx` | `active` |
| OS-02 | OS | `ss -lntp` | Nginxが80/tcpをListen |
| OS-03 | OS | `systemctl status azuremonitoragent` | AMAが`active (running)` |
| MN-01 | 監視 | CPUアラート定義を表示 | 対象VM、80%、有効 |
| MN-02 | 監視 | CPUアラートを意図的に発火させ、Action Group宛のメールを確認 | `alertEmailAddress`宛に通知が到達 |
| MN-03 | 監視 | Log AnalyticsでKQL `Perf \| where Computer contains "vm-" \| take 10` と `Syslog \| take 10` を実行 | 直近収集分のレコードが返る |
| OP-01 | 再現性 | 同一Bicepを再デプロイ | 不要な置換なし |
| CL-01 | 削除 | `remove.ps1`後にRG照会 | RGが存在しない |

## VM内確認コマンド

```bash
hostnamectl
systemctl --no-pager --full status nginx
systemctl --no-pager --full status azuremonitoragent
curl --fail http://127.0.0.1/
ss -lntp
df -h
free -m
journalctl -u nginx --since "30 minutes ago" --no-pager
```

## 異常系の安全な試験

- SSH異常試験は、自分を締め出さないよう別経路または現在のセッションを保持して行う。
- CPU負荷生成は費用・監視影響を理解した隔離学習環境だけで短時間実施する(例: `stress-ng --cpu 1 --timeout 360s`)。
- 本番や共有環境でサービス停止、DoS相当、無断スキャンを行わない。

## 合否判定

- `PASS`: 期待値と実測が一致し、証跡がある。
- `FAIL`: 不一致。原因、暫定対応、再試験予定を書く。
- `BLOCKED`: 権限や環境制約で実行不能。制約を書く。
- `NOT RUN`: 未実施。静的検証で代用したと書かない。

## 完了判定

重大度HighのFAILが0件、対象試験がすべてPASSまたは承認済みBLOCKEDであること。削除を含め、別担当者が記録だけで追跡できる状態を完了とする。
