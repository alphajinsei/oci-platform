# ---- Vault：秘密情報の置き場 ----

# DEFAULT（共有型）の Vault とソフトウェアの鍵は無料
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_id
  display_name   = "platform"
  vault_type     = "DEFAULT"

  lifecycle {
    # 消すと 7〜30 日後の削除予約になり、すぐには作り直せない
    prevent_destroy = true
  }
}

resource "oci_kms_key" "main" {
  compartment_id      = var.compartment_id
  display_name        = "platform-secrets"
  management_endpoint = oci_kms_vault.main.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

resource "oci_vault_secret" "mysql_admin_password" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = "mysql-admin-password"
  description    = "MySQL HeatWave admin password (user: admin)"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.mysql_admin.result)
  }
}

# ---- インスタンス・プリンシパル：VM 自身に IAM の権限を持たせる ----

# このコンパートメントの VM 全部を1つのグループとして扱う
resource "oci_identity_dynamic_group" "instances" {
  compartment_id = var.tenancy_id
  name           = "platform-instances"
  description    = "VMs in the oci-platform compartment"
  matching_rule  = "ALL {instance.compartment.id = '${var.compartment_id}'}"
}

resource "oci_identity_policy" "instances" {
  compartment_id = var.compartment_id
  name           = "platform-instances"
  description    = "What the platform VMs may do (instance principal)"
  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.instances.name} to read secret-family in compartment id ${var.compartment_id}",
  ]
}
