locals {
  nsgs = ["lb", "app", "mail", "ops", "db"]

  # アプリ用のポート。アプリを足すたびに開けなくて済むよう、範囲で一度に開ける
  app_ports = { min = 8000, max = 8099 }

  # Cloudflare のプロキシの送信元。LB には Cloudflare 経由でしか来させない
  cloudflare_ipv4 = compact(split("\n", trimspace(data.http.cloudflare_ipv4.response_body)))

  # peer_type：CIDR_BLOCK か NETWORK_SECURITY_GROUP（peer は CIDR か NSG のキー）
  # ports が null なら全プロトコル
  rules = concat(
    [for cidr in local.cloudflare_ipv4 : {
      nsg   = "lb", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = cidr,
      ports = { min = 443, max = 443 }, desc = "HTTPS from Cloudflare"
    }],
    [
      { nsg = "lb", direction = "EGRESS", peer_type = "NETWORK_SECURITY_GROUP", peer = "app", ports = local.app_ports, desc = "to apps" },

      { nsg = "app", direction = "INGRESS", peer_type = "NETWORK_SECURITY_GROUP", peer = "lb", ports = local.app_ports, desc = "from LB" },
      { nsg = "app", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = local.vcn_cidr, ports = { min = 22, max = 22 }, desc = "SSH via Bastion" },
      { nsg = "app", direction = "EGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = null, desc = "all outbound" },

      { nsg = "mail", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = { min = 25, max = 25 }, desc = "SMTP" },
      { nsg = "mail", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = { min = 465, max = 465 }, desc = "SMTPS (submission)" },
      { nsg = "mail", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = { min = 587, max = 587 }, desc = "submission" },
      { nsg = "mail", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = { min = 993, max = 993 }, desc = "IMAPS" },
      { nsg = "mail", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = local.vcn_cidr, ports = { min = 22, max = 22 }, desc = "SSH via Bastion" },
      { nsg = "mail", direction = "EGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = null, desc = "all outbound" },

      { nsg = "ops", direction = "INGRESS", peer_type = "CIDR_BLOCK", peer = local.vcn_cidr, ports = { min = 22, max = 22 }, desc = "SSH via Bastion" },
      { nsg = "ops", direction = "EGRESS", peer_type = "CIDR_BLOCK", peer = "0.0.0.0/0", ports = null, desc = "all outbound" },

      # 33060 は MySQL Shell などが使う X プロトコル
      { nsg = "db", direction = "INGRESS", peer_type = "NETWORK_SECURITY_GROUP", peer = "app", ports = { min = 3306, max = 3306 }, desc = "MySQL from apps" },
      { nsg = "db", direction = "INGRESS", peer_type = "NETWORK_SECURITY_GROUP", peer = "ops", ports = { min = 3306, max = 3306 }, desc = "MySQL from ops" },
      { nsg = "db", direction = "INGRESS", peer_type = "NETWORK_SECURITY_GROUP", peer = "ops", ports = { min = 33060, max = 33060 }, desc = "MySQL X from ops" },
    ],
  )
}

data "http" "cloudflare_ipv4" {
  url = "https://www.cloudflare.com/ips-v4"

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Cloudflare の IP 範囲を取得できなかった"
    }
  }
}

resource "oci_core_network_security_group" "this" {
  for_each = toset(local.nsgs)

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nsg-${each.key}"
}

resource "oci_core_network_security_group_security_rule" "this" {
  # キーは「nsg 向き 相手 ポート」。Cloudflare の範囲が変わっても、変わった分だけ作り直される
  for_each = {
    for r in local.rules :
    "${r.nsg} ${r.direction} ${r.peer} ${r.ports == null ? "all" : "${r.ports.min}-${r.ports.max}"}" => r
  }

  network_security_group_id = oci_core_network_security_group.this[each.value.nsg].id
  direction                 = each.value.direction
  protocol                  = each.value.ports == null ? "all" : "6" # 6 = TCP
  stateless                 = false
  description               = each.value.desc

  source      = each.value.direction == "INGRESS" ? (each.value.peer_type == "CIDR_BLOCK" ? each.value.peer : oci_core_network_security_group.this[each.value.peer].id) : null
  source_type = each.value.direction == "INGRESS" ? each.value.peer_type : null

  destination      = each.value.direction == "EGRESS" ? (each.value.peer_type == "CIDR_BLOCK" ? each.value.peer : oci_core_network_security_group.this[each.value.peer].id) : null
  destination_type = each.value.direction == "EGRESS" ? each.value.peer_type : null

  dynamic "tcp_options" {
    for_each = each.value.ports == null ? [] : [each.value.ports]
    content {
      destination_port_range {
        min = tcp_options.value.min
        max = tcp_options.value.max
      }
    }
  }
}
