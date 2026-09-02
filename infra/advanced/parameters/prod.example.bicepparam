// 発展編(株式会社サンライズ物産)用パラメーター例
// 使い方: このファイルを prod.bicepparam にコピーし、自分の値へ書き換える。
//   Copy-Item infra/advanced/parameters/prod.example.bicepparam infra/advanced/parameters/prod.bicepparam
// prod.bicepparam は .gitignore により除外されるため、誤ってコミットされない。
using '../main.bicep'

// リージョンは設計台帳の制約により japaneast 固定
param location = 'japaneast'

// 全VM共通のローカル管理者アカウント名(Administrator や admin のような推測されやすい名前は避ける)
param adminUsername = 'azureadmin'

// 機密値はこのファイルに直接書かず、実行時に環境変数から読み込む。
// 例(PowerShell): $env:VM_ADMIN_PASSWORD = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText
// 例(bash):       read -s VM_ADMIN_PASSWORD && export VM_ADMIN_PASSWORD
// コピー後の prod.bicepparam にも平文パスワードを書かないこと。
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
param sqlServiceAccountPassword = readEnvironmentVariable('SQL_SERVICE_ACCOUNT_PASSWORD')

// 監視アラートの通知先メールアドレス(運用担当者宛)
param alertEmailAddress = 'ops-alert@example.com'

// Key Vaultにシークレット書き込み権限を付与するEntra IDオブジェクトID。
// 空文字の場合はロール割り当てをスキップする(デプロイ後に手動で付与する)。
// 自分のオブジェクトIDは az ad signed-in-user show --query id -o tsv で確認できる。
param keyVaultAdministratorObjectId = ''
