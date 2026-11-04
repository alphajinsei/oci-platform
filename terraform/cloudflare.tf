# ---- Cloudflare（OCI の外）：このリポジトリが Cloudflare で触るのは、このファイルだけ ----
# 触るのは DNS レコードだけ（確認用のホスト名と、メールの A・MX）。暗号化モード（Full (strict)）や Origin 証明書など、
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
