# ---- Cloudflare（OCI の外）：このリポジトリが Cloudflare で触るのは、このファイルだけ ----
# 触るのは DNS レコードだけ（確認用のホスト名と、メールの A・MX・SPF・DKIM・Return-Path・DMARC）。暗号化モード（Full (strict)）や Origin 証明書など、
# ゾーンとアカウントの設定は手で行う（ロードマップの Step 5）

provider "cloudflare" {
  # 認証は環境変数 CLOUDFLARE_API_TOKEN から読む（tf.sh が .secrets から読み込む）。
  # トークンの権限は Zone Read と DNS Edit だけ
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.domain
  }
}

# 確認用のホスト名：oci-platform.alphajinsei.com → LB（既定のページが見える）
resource "cloudflare_dns_record" "platform_check" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "oci-platform.${var.domain}"
  type    = "A"
  content = local.lb_public_ip
  proxied = true # Cloudflare を通す（LB は Cloudflare の IP からしか受けない）
  ttl     = 1    # proxied のときは 1（自動）
  comment = "managed by Terraform: oci-platform"
}

# アプリ側の Terraform は、これを使って自分の DNS レコードを足す
output "cloudflare_zone_id" {
  value = data.cloudflare_zone.main.zone_id
}

# ---- メール（mail VM）。Cloudflare は SMTP や IMAP を通さないので、プロキシしない ----

# MX の向け先、メールソフトの接続先。IP は予約していないので、VM を作り直したら apply で追いつく
resource "cloudflare_dns_record" "mail" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "mail.${var.domain}"
  type    = "A"
  content = oci_core_instance.this["mail"].public_ip
  proxied = false
  ttl     = 300
  comment = "managed by Terraform: oci-platform"
}

# alphajinsei.com 宛てのメールは mail.alphajinsei.com へ
resource "cloudflare_dns_record" "mx" {
  zone_id  = data.cloudflare_zone.main.zone_id
  name     = var.domain
  type     = "MX"
  content  = cloudflare_dns_record.mail.name
  priority = 10
  ttl      = 300
  comment  = "managed by Terraform: oci-platform"
}

# ---- メールの送信の認証（SPF・DKIM・DMARC）。値の意味は docs/notes/extra-mail-basics.md の 6 ----

# SPF：envelope from が @<domain> のメールを送ってよいのは Email Delivery（アジア太平洋）だけ。
# Email Delivery 経由のメールは bounce.<domain> で SPF を受ける（下の Return-Path）ので、これはそれ以外の保険
resource "cloudflare_dns_record" "spf" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = var.domain
  type    = "TXT"
  content = "\"v=spf1 include:ap.rp.oracleemaildelivery.com -all\""
  ttl     = 300
  comment = "managed by Terraform: oci-platform"
}

# DKIM：公開鍵は Email Delivery が持ち、CNAME で指す（鍵を替えても DNS を直さなくてよい）
resource "cloudflare_dns_record" "dkim" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = oci_email_dkim.main.dns_subdomain_name
  type    = "CNAME"
  content = oci_email_dkim.main.cname_record_value
  proxied = false
  ttl     = 300
  comment = "managed by Terraform: oci-platform"
}

# カスタム Return-Path：bounce.<domain> の SPF とバウンスの受け口を、Email Delivery 側に任せる
resource "cloudflare_dns_record" "return_path" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = oci_email_email_return_path.main.dns_subdomain_name
  type    = "CNAME"
  content = oci_email_email_return_path.main.cname_record_value
  proxied = false
  ttl     = 300
  comment = "managed by Terraform: oci-platform"
}

# DMARC：From: が @<domain> のメールの扱い。まずは p=none（何もしない）で、レポートを dmarc@ に受け取る
resource "cloudflare_dns_record" "dmarc" {
  zone_id = data.cloudflare_zone.main.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:dmarc@${var.domain}\""
  ttl     = 300
  comment = "managed by Terraform: oci-platform"
}
