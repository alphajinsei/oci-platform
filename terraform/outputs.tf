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
