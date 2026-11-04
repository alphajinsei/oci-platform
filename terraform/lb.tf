# ---- 公開：Cloudflare → Flexible LB（443、TLS はここで終わる）→ app VM ----
# Cloudflare 側（DNS レコード）は cloudflare.tf

# Cloudflare → LB の区間の証明書（Cloudflare Origin CA。Cloudflare だけが信頼する）。
# ダッシュボードで手で発行し（15年）、.secrets に置いたものを読む。秘密鍵は state にも残る
# （state は非公開のバケットにある）
locals {
  origin_cert = file(pathexpand(var.origin_cert_path))
  origin_key  = file(pathexpand(var.origin_key_path))
}

resource "oci_load_balancer_load_balancer" "main" {
  compartment_id             = var.compartment_id
  display_name               = "platform"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.this["lb"].id]
  network_security_group_ids = [oci_core_network_security_group.this["lb"].id]
  is_private                 = false

  # Always Free は 10Mbps 固定
  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }
}

# LB の証明書は書き換えられないので、中身が変わったら別の名前で作ってから古いものを消す
resource "oci_load_balancer_certificate" "origin" {
  load_balancer_id   = oci_load_balancer_load_balancer.main.id
  certificate_name   = "cloudflare-origin-${substr(sha1(local.origin_cert), 0, 8)}"
  public_certificate = local.origin_cert
  private_key        = local.origin_key

  lifecycle {
    create_before_destroy = true
  }
}

# ---- どのアプリにも当たらないホスト名の行き先：app VM の 8000 番の既定のページ ----
# アプリは自分のリポジトリの Terraform で、ホスト名付きのリスナーとバックエンド・セットを足す

resource "oci_load_balancer_backend_set" "default" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  name             = "default"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol    = "HTTP"
    port        = local.default_site_port
    url_path    = "/"
    return_code = 200
  }
}

resource "oci_load_balancer_backend" "default" {
  load_balancer_id = oci_load_balancer_load_balancer.main.id
  backendset_name  = oci_load_balancer_backend_set.default.name
  ip_address       = oci_core_instance.this["app"].private_ip
  port             = local.default_site_port
}

# ホスト名を持たないリスナー＝ 443 番の既定。アプリのリスナーはホスト名付きで同じ 443 番に並ぶ
resource "oci_load_balancer_listener" "https_default" {
  load_balancer_id         = oci_load_balancer_load_balancer.main.id
  name                     = "https-default"
  default_backend_set_name = oci_load_balancer_backend_set.default.name
  port                     = 443
  protocol                 = "HTTP"

  # TLS 1.2 だけにしている（既定の暗号スイートが 1.2 用）。1.3 や PQC は、暗号スイートを替えて後で試す
  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.origin.certificate_name
    protocols               = ["TLSv1.2"]
    verify_peer_certificate = false
  }
}

locals {
  default_site_port = 8000 # 台帳の 8000 番は共通基盤の既定のページ。アプリは 8001 から
  lb_public_ip      = [for ip in oci_load_balancer_load_balancer.main.ip_address_details : ip.ip_address if ip.is_public][0]
}
