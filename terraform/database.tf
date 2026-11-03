# ---- MySQL HeatWave（Always Free：MySQL.Free、1台、データ 50GB） ----

# 管理者のパスワードは Terraform が作り、Vault に入れる（vault.tf）。
# 値は state にも残る（state は非公開のバケットにある）
resource "random_password" "mysql_admin" {
  length           = 24
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#%*-_=+"
}

# HeatWave は、サブネットへの VNIC の作成と NSG への参加を、DB システム自身の権限
# （リソース・プリンシパル）で行う。管理者の権限は使われないので、別にポリシーが要る。
# ないと CreateInternalVnic が 404 になり、DB システムが FAILED になる。
# https://docs.oracle.com/en-us/iaas/mysql-database/doc/mandatory-policies-permissions.html
resource "oci_identity_policy" "mysql" {
  compartment_id = var.compartment_id
  name           = "platform-mysql"
  description    = "Let MySQL DB systems in this compartment attach VNICs and join NSGs"
  statements = [
    "Allow any-user to {NETWORK_SECURITY_GROUP_UPDATE_MEMBERS} in compartment id ${var.compartment_id} where all {request.principal.type='mysqldbsystem', request.resource.compartment.id='${var.compartment_id}'}",
    "Allow any-user to {VNIC_CREATE, VNIC_UPDATE, VNIC_ASSOCIATE_NETWORK_SECURITY_GROUP, VNIC_DISASSOCIATE_NETWORK_SECURITY_GROUP} in compartment id ${var.compartment_id} where all {request.principal.type='mysqldbsystem', request.resource.compartment.id='${var.compartment_id}'}",
  ]
}

resource "oci_mysql_mysql_db_system" "main" {
  # ポリシーが効いてから作る
  depends_on = [oci_identity_policy.mysql]

  compartment_id          = var.compartment_id
  availability_domain     = local.ad
  display_name            = "platform-mysql"
  shape_name              = "MySQL.Free"
  is_highly_available     = false
  data_storage_size_in_gb = 50

  subnet_id      = oci_core_subnet.this["db"].id
  nsg_ids        = [oci_core_network_security_group.this["db"].id]
  hostname_label = "mysql" # mysql.db.platform.oraclevcn.com

  admin_username = "admin"
  admin_password = random_password.mysql_admin.result

  # バックアップの設定（backup_policy）は書かない。Always Free では作成時に指定できず、
  # OCI が決めた既定の自動バックアップになる（中身はコンソールで確かめる）

  # terraform destroy や手違いで消えないようにする
  deletion_policy {
    is_delete_protected        = true
    automatic_backup_retention = "DELETE"
    final_backup               = "SKIP_FINAL_BACKUP"
  }

  lifecycle {
    # バージョンは作ったときの既定のまま。上がるのは OCI のメンテナンスに任せる。
    # バックアップの設定は OCI が決めるので、差分として扱わない
    ignore_changes = [admin_password, mysql_version, backup_policy]
  }
}
