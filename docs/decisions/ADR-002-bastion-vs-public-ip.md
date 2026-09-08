# ADR-002: 管理アクセス経路をPublic IP直結のままとし、Bastion/VPNは対象外とする

- 状態: Accepted
- 日付: 2026-09-08
- 要件・課題: [不足点と学習ロードマップ](../09-gap-analysis-and-roadmap.md)は「高: HTTPSと安全な管理経路」を挙げ、現状の「SSHを`adminCidr`のみへ許可したPublic IP直結」構成が本番想定の保護として不足すると指摘している。Stage 4の改善候補「Bastion/VPN案とPublic IP案を費用・運用・リスクで比較する」に対応する。
- 制約:
  - 本教材は従業員50名規模の小規模案件(Sample Works)を想定し、学習コストと構築コストを最小に保つ方針([README](../../README.md)「コスト配慮」参照)。
  - 実Azure環境への課金・認証情報を使わずにドキュメント上の比較として実施する(実機検証は[10. Stage 3実施ランブック](10-stage3-runbook.md)で利用者が行う)。
  - 既存の`adminCidr`によるSSH制限、パスワード認証無効化という安全策は維持する。
- 選択肢:
  - 案A(現状維持): Public IPを直結し、NSGで`adminCidr`のみSSH許可を継続する。
  - 案B: Azure Bastionを追加し、Public IPをVMから外してBastion経由でのみSSH接続する。
  - 案C: VPN Gateway(Point-to-Site等)を追加し、VNet内プライベートIP経由でのみSSH接続する。
- 判断: 案A(現状維持)を採用し、案B・案Cは「本番相当の要件が生じた場合の拡張候補」として不採用のまま明記する。

## 比較表

| 観点 | 案A: Public IP直結(現状) | 案B: Azure Bastion | 案C: VPN Gateway (P2S) |
|---|---|---|---|
| 概算コスト(月額目安) | 追加コストなし(VM本体費用のみ) | Bastion Basic SKUの固定費が常時発生(VMより高額になりやすい) | VPN Gatewayの固定費(SKUによるが小規模帯でも常時発生)+クライアント証明書運用 |
| 構築の複雑さ | 低(NSG 1ルールのみ) | 中(専用Subnet`AzureBastionSubnet`、Public IPをBastion側に付け替え) | 中〜高(証明書発行、クライアント設定配布、Point-to-Siteアドレスプール設計) |
| 運用負荷 | 低(`adminCidr`の見直しのみ) | 低〜中(Bastionの可用性・SKU管理) | 中(証明書失効・更新、利用者ごとのクライアント設定配布) |
| セキュリティ | 中(VMにPublic IPが露出、`adminCidr`で絞るのみ) | 高(VMからPublic IPを排除、Azure Portal経由の踏み台接続、セッション記録が可能) | 高(VMからPublic IPを排除、閉域網接続) |
| 学習教材としての適合性 | 高(未経験者がNSG/Public IPの役割を最短で理解できる) | 中(専用Subnet設計など追加の前提知識が必要) | 低(証明書運用など学習コストが高く、案件規模に対して過剰) |
| 本教材の想定規模(従業員50名、単一VM)との整合 | 高 | 低(固定費が単一VMの学習用途に対して不釣り合い) | 低(同上、かつ運用負荷が本教材の目的を超える) |

## 理由

- 本教材は「未経験者が要件定義から運用までの一連の工程を学ぶ」ことが目的であり、README記載の「コスト配慮」「小さいVM」という方針と、案B・Cの固定費常時発生は整合しない。
- 現状の`adminCidr`制限とパスワード認証無効化により、学習用途としては最小限の安全性を満たしている。
- 案B(Bastion)は、より実務に近い規模の案件を扱う[発展編](../advanced/00-overview-requirements.md)ですでに採用しており(`infra/advanced/`のAzure Bastion参照)、「小規模案件では直結、中規模以上ではBastion」という段階的な設計判断を教材全体で示せる。
- 本番相当の可用性・セキュリティ要件が生じた場合は、[基本設計書「5. 将来構成」](03-basic-design.md#5-将来構成)に記載の通り、Bastion/VPN、Private Endpoint等を再検討する。

## 影響

- 得られる効果: 「なぜBastion/VPNを採用しないか」を理由付きで説明できるようになり、[08. ポートフォリオ説明](08-portfolio-guide.md)の「弱点を3つ挙げ、改善順を説明する」という面接前チェックに使える具体的な比較材料が増える。
- 新たな欠点: 現状の構成のまま運用した場合、VMへの直接攻撃面(Public IP露出)は残り続ける。`adminCidr`の設定ミスや管理者PCのIP変動時の運用負荷は解消されない。

## 検証

- ドキュメントレビュー: 本ADRの比較表と理由が、README「安全ルール」「コスト配慮」の方針と矛盾しないこと。
- 実施しない項目のため試験IDは付与しない。要件トレーサビリティ表(09-gap-analysis-and-roadmap.md)の該当項目には、本ADRを「対象外とした理由」として引用する。

## 見直し条件

- 単一VMから複数VM・本番運用へ移行する場合。
- 管理者の接続元IPが頻繁に変わり、`adminCidr`の運用負荷が高くなった場合。
- 案件の想定顧客規模が拡大し、[発展編](../advanced/00-overview-requirements.md)相当の要件になった場合(その場合は発展編のBastion構成を参照する)。
