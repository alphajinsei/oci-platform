# 後の Step と、アプリ側の Terraform（terraform_remote_state）から使う

output "compartment_id" {
  value = var.compartment_id
}

output "vcn_id" {
  value = oci_core_vcn.main.id
}

output "subnet_ids" {
  value = { for k, s in oci_core_subnet.this : k => s.id }
}

output "nsg_ids" {
  value = { for k, n in oci_core_network_security_group.this : k => n.id }
}

output "app_ports" {
  value = local.app_ports
}

output "instances" {
  value = {
    for k, i in oci_core_instance.this : k => {
      id         = i.id
      private_ip = i.private_ip
      public_ip  = i.public_ip
    }
  }
}

output "bastion_id" {
  value = oci_bastion_bastion.main.id
}

output "mysql" {
  value = {
    host    = "${oci_mysql_mysql_db_system.main.hostname_label}.${oci_core_subnet.this["db"].subnet_domain_name}"
    ip      = oci_mysql_mysql_db_system.main.ip_address
    port    = oci_mysql_mysql_db_system.main.port
    version = oci_mysql_mysql_db_system.main.mysql_version
  }
}

output "vault_id" {
  value = oci_kms_vault.main.id
}

output "mysql_admin_secret_name" {
  value = oci_vault_secret.mysql_admin_password.secret_name
}

# アプリ側の Terraform は、これを使ってホスト名付きのリスナーとバックエンド・セットを足す
output "lb" {
  value = {
    id               = oci_load_balancer_load_balancer.main.id
    public_ip        = local.lb_public_ip
    certificate_name = oci_load_balancer_certificate.origin.certificate_name
  }
}

# cloudflare_zone_id は cloudflare.tf
