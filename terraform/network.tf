locals {
  vcn_cidr = "10.0.0.0/16"

  # rt：どのルート表を使うか（public / private / db）
  subnets = {
    lb  = { name = "public-lb", cidr = "10.0.0.0/24", rt = "public" }
    dmz = { name = "public-dmz", cidr = "10.0.1.0/24", rt = "public" }
    app = { name = "private-app", cidr = "10.0.10.0/24", rt = "private" }
    db  = { name = "private-db", cidr = "10.0.20.0/24", rt = "db" }
    ops = { name = "private-ops", cidr = "10.0.30.0/24", rt = "private" }
  }
}

resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_id
  display_name   = "platform"
  cidr_blocks    = [local.vcn_cidr]
  dns_label      = "platform"
}

# ---- ゲートウェイ ----

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "igw"
  enabled        = true
}

resource "oci_core_nat_gateway" "nat" {
  count          = var.use_nat_gateway ? 1 : 0
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nat"
}

# OCI のサービス（OCIR、Object Storage、Vault など）へ、インターネットを通らずに出る出口
data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_service_gateway" "sgw" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "sgw"
  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

# ---- ルート表 ----

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-private"

  # 外へは NAT から。NAT を使わないときは Internet GW から（サブネットも公開になる）
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = var.use_nat_gateway ? oci_core_nat_gateway.nat[0].id : oci_core_internet_gateway.igw.id
  }

  dynamic "route_rules" {
    for_each = var.use_nat_gateway ? [1] : []
    content {
      destination       = data.oci_core_services.all.services[0].cidr_block
      destination_type  = "SERVICE_CIDR_BLOCK"
      network_entity_id = oci_core_service_gateway.sgw.id
    }
  }
}

# DB は外に出ない
resource "oci_core_route_table" "db" {
  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = "rt-db"
}

# ---- セキュリティ・リスト ----

# 通信の許可は NSG（nsg.tf）で行う。VCN の既定のセキュリティ・リストは、
# 何もしないと SSH を 0.0.0.0/0 から許しているので、ICMP（経路の MTU の調整用）だけにする
resource "oci_core_default_security_list" "default" {
  manage_default_resource_id = oci_core_vcn.main.default_security_list_id
  display_name               = "default (rules are in NSGs)"

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = local.vcn_cidr
    icmp_options {
      type = 3
    }
  }
}

# ---- サブネット ----

resource "oci_core_subnet" "this" {
  for_each = local.subnets

  compartment_id = var.compartment_id
  vcn_id         = oci_core_vcn.main.id
  display_name   = each.value.name
  cidr_block     = each.value.cidr
  dns_label      = each.key
  route_table_id = {
    public  = oci_core_route_table.public.id
    private = oci_core_route_table.private.id
    db      = oci_core_route_table.db.id
  }[each.value.rt]
  security_list_ids = [oci_core_vcn.main.default_security_list_id]

  # private のサブネットの VM には公開 IP を付けさせない（NAT を使わないときは付ける）
  prohibit_public_ip_on_vnic = each.value.rt == "db" || (each.value.rt == "private" && var.use_nat_gateway)
}
