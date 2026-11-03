locals {
  # A1 は計 2 OCPU / 12GB まで（Always Free）。マイクロは 1/8 OCPU / 1GB で、shape_config は付けない
  vms = {
    app = {
      shape  = "VM.Standard.A1.Flex", ocpus = 1, memory = 8,
      subnet = "app", nsg = "app", private_ip = "10.0.10.10"
    }
    mail = {
      shape  = "VM.Standard.A1.Flex", ocpus = 1, memory = 4,
      subnet = "dmz", nsg = "mail", private_ip = "10.0.1.10"
    }
    ops = {
      shape  = "VM.Standard.E2.1.Micro", ocpus = null, memory = null,
      subnet = "ops", nsg = "ops", private_ip = "10.0.30.10"
    }
  }

  ad = data.oci_identity_availability_domains.ads.availability_domains[0].name
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_id
}

# Ubuntu 24.04 の最新のイメージ（Minimal ではない方）。Arm（A1）と x86（マイクロ）で別
data "oci_core_images" "os" {
  for_each = toset(distinct([for v in local.vms : v.shape]))

  compartment_id           = var.compartment_id
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = each.key
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "this" {
  for_each = local.vms

  compartment_id      = var.compartment_id
  availability_domain = local.ad
  display_name        = each.key
  shape               = each.value.shape

  dynamic "shape_config" {
    for_each = each.value.ocpus == null ? [] : [1]
    content {
      ocpus         = each.value.ocpus
      memory_in_gbs = each.value.memory
    }
  }

  create_vnic_details {
    subnet_id      = oci_core_subnet.this[each.value.subnet].id
    nsg_ids        = [oci_core_network_security_group.this[each.value.nsg].id]
    private_ip     = each.value.private_ip
    hostname_label = each.key
    # mail は外から直接受けるので公開 IP を持つ。NAT を使わないときは app と ops も持つ
    assign_public_ip = each.value.subnet == "dmz" || !var.use_nat_gateway
  }

  # ブートボリュームはイメージの既定（47GB）。3台で 141GB（上限 200GB。足りなくなったら止めずに大きくできる）。
  # mail のデータもブートボリュームの /srv/mail に置く（ブロックボリュームは最小 50GB で枠を食うため）
  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.os[each.value.shape].images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(pathexpand(var.ssh_public_key_path))
  }

  lifecycle {
    # 新しいイメージが出ても、鍵を替えても、作り直さない（作り直したいときは -replace で）
    ignore_changes = [source_details[0].source_id, metadata]
  }
}

# ---- Bastion：VM の 22 番への入口 ----

resource "oci_bastion_bastion" "main" {
  bastion_type     = "STANDARD"
  compartment_id   = var.compartment_id
  target_subnet_id = oci_core_subnet.this["app"].id
  name             = "platform"

  # 自宅の IP は変わるので絞らない（入るには、OCI の認証と、セッションに登録した鍵の両方が要る）
  client_cidr_block_allow_list = ["0.0.0.0/0"]
  max_session_ttl_in_seconds   = 10800
}

# ssh の設定を書き出す。~/.ssh/config から Include して、`ssh oci-app` のように使う
resource "local_file" "ssh_config" {
  filename        = "${path.module}/../ssh_config"
  file_permission = "0644"
  content = templatefile("${path.module}/ssh_config.tftpl", {
    bastion_id = oci_bastion_bastion.main.id
    proxy      = abspath("${path.module}/../bin/bastion-proxy")
    key        = var.ssh_private_key_path
    hosts      = { for k, v in local.vms : "oci-${k}" => v.private_ip }
  })
}
