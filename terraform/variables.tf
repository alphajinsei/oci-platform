variable "tenancy_id" {
  description = "テナンシー（ルートのコンパートメント）。AD の一覧を引くのに使う"
  type        = string
}

variable "compartment_id" {
  description = "共通基盤のリソースを置くコンパートメント（oci-platform）"
  type        = string
}

variable "region" {
  description = "ホームリージョン。Always Free のリソースはここに作る"
  type        = string
}

variable "use_nat_gateway" {
  description = "false にすると、app と ops を公開サブネットにして Internet GW から外に出す（NAT が課金されていた場合の逃げ道）"
  type        = bool
  default     = true
}

variable "ssh_public_key_path" {
  description = "VM に登録する公開鍵（Bastion のセッションは RSA しか受け付けないので、別の鍵 ~/.ssh/oci-platform-bastion を使う）"
  type        = string
  default     = "~/.ssh/oci-platform.pub"
}

variable "ssh_private_key_path" {
  description = "上の公開鍵と対の秘密鍵（ssh の設定に書くだけで、Terraform は読まない）"
  type        = string
  default     = "~/.ssh/oci-platform"
}

variable "domain" {
  description = "Cloudflare で管理しているドメイン。アプリは <名前>.<domain> で公開する"
  type        = string
  default     = "alphajinsei.com"
}

variable "origin_cert_path" {
  description = "Cloudflare の Origin 証明書（ダッシュボードで手で発行したもの、PEM）"
  type        = string
  default     = "~/claude-sandbox/infra/.secrets/oci-platform-origin.pem"
}

variable "origin_key_path" {
  description = "上の証明書の秘密鍵（PEM）"
  type        = string
  default     = "~/claude-sandbox/infra/.secrets/oci-platform-origin.key"
}
