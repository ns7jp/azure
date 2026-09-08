# 05. 構築手順書

## フェーズA: 事前確認

```powershell
az version
az bicep version
az login
az account show --output table
```

確認点:

- 表示されたサブスクリプション名・IDは学習用か。
- Contributor相当の作成権限があるか。
- 予算アラートはAzure Portal側で設定済みか。
- SSH公開鍵があり、秘密鍵を安全に保管したか。
- CPU/バックアップアラートを受け取るメールアドレスを用意したか。

鍵がない場合（既存ファイルを上書きしない）:

```powershell
ssh-keygen -t ed25519 -C "azure-portfolio" -f "$env:USERPROFILE/.ssh/azure_portfolio"
```

## フェーズB: パラメーター準備

```powershell
Copy-Item infra/parameters/dev.example.bicepparam infra/parameters/dev.bicepparam
```

編集する値:

- `owner`: 個人メールではなくGitHub名等の非機密識別子
- `sshPublicKey`: `.pub` の1行。秘密鍵ではない
- `adminCidr`: 現在のグローバルIPv4 `/32`
- `openHttp`: Web確認が必要な短時間だけ `true`
- `alertEmailAddress`: CPUアラート・バックアップジョブ失敗通知(Action Group)を受け取るメールアドレス。プレースホルダーのままだと`deploy.ps1`が停止する

`dev.bicepparam` は `.gitignore` 対象である。念のためコミット前に `git diff --cached` を確認する。

## フェーズC: 静的検証とWhat-If

```powershell
az bicep build --file infra/main.bicep
./scripts/deploy.ps1 -ParameterFile infra/parameters/dev.bicepparam
```

What-Ifで次を確認する。

- 削除 (`Delete`) がない。
- 対象リソースグループ、リージョン、名前が設計書と一致する。
- SSH許可元が自分の `/32` である。
- 想定外の高額SKUやサービスがない。

## フェーズD: 構築

```powershell
./scripts/deploy.ps1 -ParameterFile infra/parameters/dev.bicepparam -Apply
```

終了コードが0であることを確認し、出力を `evidence/deployment-record.example.md` のコピーへ転記する。サブスクリプションID等はマスクする。

## フェーズE: 確認

```powershell
./scripts/verify.ps1 -ResourceGroupName rg-portfolio-dev-jpe-001
az vm get-instance-view --resource-group rg-portfolio-dev-jpe-001 --name vm-portfolio-dev-jpe-001 --query instanceView.statuses --output table
```

HTTPを開けた場合:

```powershell
$ip = az network public-ip show --resource-group rg-portfolio-dev-jpe-001 --name pip-portfolio-dev-jpe-001 --query ipAddress --output tsv
curl.exe --fail --max-time 10 "http://$ip"
```

## ロールバック

デプロイ途中の失敗では、むやみに再実行しない。

1. `az deployment sub show` と Activity Logで失敗箇所を確認。
2. パラメーター、権限、SKU、クォータを確認。
3. 部分作成されたリソースを一覧化。
4. 修正してWhat-Ifするか、学習用RG全体を削除するか判断。

## 構築後の安全化

- Web確認後は `openHttp=false` に戻して再デプロイする。
- 作業場所が変わったら `adminCidr` を更新する。
- 学習を中断する場合、VMの停止だけではPublic IPやDisk等の課金が残り得る。不要ならRGを削除する。
- Recovery Services VaultにバックアップされたVMがある状態でRGを削除する場合は `scripts/remove.ps1` を使う。`az group delete` を直接実行すると、バックアップ保護が残っていて削除に失敗することがある(`remove.ps1` は削除前に自動でバックアップ保護を解除する)。
