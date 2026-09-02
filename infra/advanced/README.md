# Azure Bicep IaC(参考実装)

## デプロイ手順概要(az deployment group create を使用)

### 前提条件
1. Azure CLI (`az`) がインストール済みで `az login` 済みであること
2. デプロイ対象のリソースグループ `rg-sanrise-prod-jpe` を Japan East リージョンに事前作成しておくこと
   ```bash
   az group create --name rg-sanrise-prod-jpe --location japaneast
   ```
3. `az bicep upgrade` で Bicep CLI を最新化しておくこと

### 事前検証(必須)
実際にデプロイする前に、必ず以下を実行して構文エラーやリソース差分を確認してください。
```bash
# 1) 構文チェック(ARM JSONへのコンパイルが通るか)
az bicep build --file infra/advanced/main.bicep

# 2) デプロイ内容の事前検証
az deployment group validate \
  --resource-group rg-sanrise-prod-jpe \
  --template-file infra/advanced/main.bicep \
  --parameters adminUsername='<VM管理者ユーザー名>' \
               alertEmailAddress='<通知先メールアドレス>'

# 3) 実際に作成/変更されるリソースの差分確認(What-If)
az deployment group what-if \
  --resource-group rg-sanrise-prod-jpe \
  --template-file infra/advanced/main.bicep \
  --parameters adminUsername='<VM管理者ユーザー名>' \
               alertEmailAddress='<通知先メールアドレス>'
```
`adminPassword` と `sqlServiceAccountPassword` は @secure() パラメータのため、コマンドライン直書きは避け、実行時にプロンプトで入力するか、パラメータファイル(.bicepparam や .json)+ Key Vault参照、あるいは対話的に `--parameters adminPassword=` を空にして実行時プロンプトで入力する方法を推奨します。

### デプロイ実行
```bash
az deployment group create \
  --name deploy-sanrise-$(date +%Y%m%d%H%M) \
  --resource-group rg-sanrise-prod-jpe \
  --template-file infra/advanced/main.bicep \
  --parameters adminUsername='<VM管理者ユーザー名>' \
               alertEmailAddress='<通知先メールアドレス>' \
               keyVaultAdministratorObjectId='<KeyVaultにシークレットを書き込む権限を持たせたいEntra IDオブジェクトID(任意)>'
# adminPassword / sqlServiceAccountPassword はプロンプトで入力されます(パラメータファイルに @secure() の値を平文で残さないこと)
```

デプロイは以下の順序でモジュールを構成します(main.bicep内の依存関係により自動的に直列化されます)。
1. `modules/network.bicep` — VNet・5つのサブネット・NSGとその関連付け
2. `modules/security.bicep` — Azure Bastion、Key Vault(管理者パスワード/SQLパスワードをシークレット登録)
3. `modules/compute.bicep` — 5台のVM(vm-ad01, vm-web01, vm-ap01, vm-db01, vm-file01)とNIC
4. `modules/backup.bicep` — Recovery Services Vault、バックアップポリシー、VM保護登録
5. `modules/monitoring.bicep` — Log Analyticsワークスペース、監視エージェント、アラート一式

### デプロイ後に必要な手動作業(IaCだけでは完結しない項目)
デプロイが成功しても、以下は各モジュールのコメントに記載の通り別途実施が必要です。
- Microsoft Entra IDでの管理者ロール割り当て・条件付きアクセス/MFAポリシー設定
- vm-ad01のADドメインコントローラ昇格・DNS構成
- vm-web01/vm-ap01への既存業務アプリケーションの移設と動作確認
- vm-db01のSQL Server初期構成、TDE有効化、SQL Server workloadバックアップ(トランザクションログ15分間隔)の登録
- vm-file01の共有フォルダ作成とデータ移行
- Azure Bastion経由の実際のRDP接続確認
- Microsoft Defender for Cloud(Defender for Servers)のサブスクリプションスコープでの有効化
- 初回バックアップ完了後のリストア検証・DR訓練の実施

### パラメーターファイルを使う場合(推奨)

毎回コマンドラインに値を並べる代わりに、`parameters/prod.example.bicepparam` をコピーして使えます。機密値(`adminPassword` / `sqlServiceAccountPassword`)はファイルに書かず、`readEnvironmentVariable()` で環境変数から読み込む形になっています。

```bash
cp infra/advanced/parameters/prod.example.bicepparam infra/advanced/parameters/prod.bicepparam
# prod.bicepparam の alertEmailAddress 等を自分の値へ変更(コピー先は .gitignore で除外済み)

read -s VM_ADMIN_PASSWORD && export VM_ADMIN_PASSWORD
read -s SQL_SERVICE_ACCOUNT_PASSWORD && export SQL_SERVICE_ACCOUNT_PASSWORD

az deployment group what-if \
  --resource-group rg-sanrise-prod-jpe \
  --template-file infra/advanced/main.bicep \
  --parameters infra/advanced/parameters/prod.bicepparam
```

What-Ifの結果を確認したうえで、`what-if` を `create` に置き換えて実行します。

### 注意事項
- 本コードは学習・ポートフォリオ用の参考実装です。実際の本番運用に用いる場合は、料金・可用性・セキュリティ要件を自社ポリシーに照らして必ずレビューし、`az bicep build` / `az deployment group what-if` による事前検証を行ってください。
- パスワード等の機密値はコード中に直書きせず、@secure() パラメータおよびAzure Key Vaultで管理する設計としています。

