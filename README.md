# Azure構築案件パック(未経験からのサーバー構築エンジニア・ポートフォリオ)

**未経験からサーバー構築/インフラエンジニアへのキャリアチェンジを目指す人向けの、Azure構築案件の設計書一式(全13章)とIaC(Bicep)のポートフォリオです。**

架空の中堅商社「株式会社サンライズ物産」が、老朽化したオンプレミス基幹サーバー(受発注・在庫管理システム)をAzureへリフト&シフトする、という実務に近い設定のもとで、**要件定義 → 基本設計 → 詳細設計 → 構築手順 → テスト → 用語集 → 面接でのアピール方法**まで、実務の一連の流れを疑似体験できるように作成しています。

専門用語には初出時に簡単な注釈を付け、各章の冒頭に要点、末尾に理解度チェック(Q&A)を用意するなど、**初心者でも読み進めながら無理なく理解・記憶できること**を最優先に設計しました。

> 登場する企業名・人物・数値等はすべて学習目的の架空の設定であり、実在の企業・団体とは一切関係ありません。

## この案件の概要

| 項目 | 内容 |
|---|---|
| 想定クライアント | 株式会社サンライズ物産(架空・卸売業・従業員約182名) |
| 課題 | 基幹サーバーのハードウェア保守切れ、OSサポート切れ、単一拠点によるBCPリスク、属人化した管理アクセス、目視監視、テープバックアップ未検証 |
| 対応方針 | Azure VM(IaaS)へのリフト&シフト、Bastion経由の統制された管理アクセス、Key Vault + Entra IDによる最小権限のセキュリティ、Log Analyticsによる予兆監視、Recovery Services Vaultによる自動バックアップ |
| リージョン | Japan East(japaneast)単一リージョン |
| 命名規則 | Microsoft Cloud Adoption Framework(CAF)準拠 |

全体構成(VNet・5サブネット・5台のVM・Bastion・監視・バックアップ)の詳細は [`docs/01-architecture.md`](docs/01-architecture.md) の構成図を参照してください。

## ドキュメント構成

| No. | ドキュメント | 内容概要 |
|---|---|---|
| 00 | [案件概要・要件定義書](docs/00-overview-requirements.md) | 架空クライアントの背景・課題、機能要件/非機能要件/制約条件 |
| 01 | [全体アーキテクチャ設計書](docs/01-architecture.md) | Azure構成図(Mermaid)、サービス選定理由、CAF命名規則 |
| 02 | [ネットワーク設計書](docs/02-network-design.md) | VNet/サブネット構成、IPアドレス設計、NSGルールの読み方 |
| 03 | [サーバー設計書](docs/03-server-design.md) | 各VM(AD/Web/AP/DB/ファイルサーバー)のスペック・役割・ディスク構成 |
| 04 | [セキュリティ設計書](docs/04-security-design.md) | NSGルール一覧、Bastion、Key Vault、Entra ID/RBAC、暗号化方針 |
| 05 | [運用監視設計書](docs/05-operations-monitoring.md) | Log Analytics、アラート設計、日常運用・パッチ適用・障害対応フロー |
| 06 | [バックアップ・DR設計書](docs/06-backup-dr.md) | Recovery Services Vault、RPO/RTO、簡易DR方針 |
| 07 | [コスト設計書](docs/07-cost-design.md) | 月額コスト試算・内訳、コスト最適化のアイデア |
| 08 | [構築手順書(ネットワーク編)](docs/08-construction-procedure-network.md) | ポータル操作ベースのネットワーク基盤構築手順 |
| 09 | [構築手順書(サーバー編)](docs/09-construction-procedure-server.md) | 各VMの作成からOS初期設定・役割設定までの手順 |
| 10 | [テスト仕様書](docs/10-test-plan.md) | 接続性・セキュリティ・可用性・バックアップ試験のテストケース |
| 11 | [用語集](docs/11-glossary.md) | 本パック全体で登場する専門用語の初心者向け解説 |
| 12 | [ポートフォリオ活用ガイド](docs/12-portfolio-guide.md) | 面接での説明方法、想定質問と回答例、今後の発展課題 |

## IaC(Infrastructure as Code)

上記の設計書で定義した内容を、学習・ポートフォリオ用のBicepテンプレートとして [`iac/bicep/`](iac/bicep/) 配下にまとめています。

```
iac/bicep/
├── main.bicep                 # エントリポイント(各モジュールの呼び出し)
└── modules/
    ├── network.bicep           # VNet・サブネット・NSG
    ├── security.bicep          # Azure Bastion・Key Vault
    ├── compute.bicep           # 5台のVM・NIC
    ├── monitoring.bicep        # Log Analytics・アラート
    └── backup.bicep            # Recovery Services Vault・バックアップポリシー
```

実際にデプロイする前には、必ず `az bicep build` や `az deployment group what-if` などで検証してください。パスワード等の機密値は `@secure()` パラメータで受け渡す設計としており、コード中にハードコードはしていません。AD昇格やSQL Server初期設定など、IaCだけで完結しない作業は各Bicepファイル内のコメントに明記しています。デプロイ手順の詳細は [`iac/README.md`](iac/README.md) を参照してください。

## このポートフォリオの使い方

1. まず [`docs/00-overview-requirements.md`](docs/00-overview-requirements.md) で案件の背景と要件を把握する
2. [`docs/01-architecture.md`](docs/01-architecture.md) で全体像をつかむ
3. 02〜07章で各領域(ネットワーク/サーバー/セキュリティ/運用監視/バックアップ/コスト)の設計を読む
4. 08〜09章の構築手順書で、実際にAzureポータル上で手を動かして検証する(任意)
5. 10章でテスト観点を確認し、11章の用語集で専門用語を復習する
6. 12章を参考に、転職活動・面接でこのポートフォリオをどう説明するか整理する

## ライセンス

[LICENSE](LICENSE) を参照してください。
