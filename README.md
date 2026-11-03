# oci-platform

OCI Always Free の上に作る、個人サービス用の共通基盤（方式③）。Cloudflare → Flexible LB → Docker ホスト → MySQL HeatWave の3層と、メールなど VM 単体のサービスの置き場を持つ。

- なぜこの構成か：[方式検討：OCI](https://github.com/alphajinsei/cf-infra-playbook/blob/main/docs/design/oci.md)
- 作る手順と進み具合：[学習ロードマップ：OCI](https://github.com/alphajinsei/cf-infra-playbook/blob/main/docs/roadmaps/oci.md)

アプリが受け取るもの・守ること（共通基盤の仕様）と、ポートの台帳は、Step 9 でここに書く。

## 構成

```
terraform/
├── versions.tf       providers, backend (state in Object Storage: tfstate/oci-platform/terraform.tfstate)
├── variables.tf      inputs
├── terraform.tfvars  compartment OCID, region (identifiers, not secrets)
├── network.tf        VCN 10.0.0.0/16, 5 subnets, Internet / NAT / Service gateways, route tables
├── nsg.tf            nsg-lb / app / mail / ops / db and their rules
└── outputs.tf        IDs for later steps and for apps (terraform_remote_state)
```

| サブネット | CIDR | 置くもの |
| --- | --- | --- |
| public-lb | 10.0.0.0/24 | Flexible LB |
| public-dmz | 10.0.1.0/24 | mail |
| private-app | 10.0.10.0/24 | Docker ホスト |
| private-db | 10.0.20.0/24 | MySQL HeatWave |
| private-ops | 10.0.30.0/24 | 作業用 兼 バッチ |

## 使い方

認証は `~/.oci/config` の DEFAULT プロファイル（API キーは `~/claude-sandbox/infra/.secrets/oci/`）。

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

- NAT Gateway が課金されていたら、`terraform.tfvars` に `use_nat_gateway = false` を足して apply する（app と ops が公開サブネットになり、Internet GW から外に出る。サブネットは作り直しになる）。
