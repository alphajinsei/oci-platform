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
