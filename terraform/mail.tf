# ---- メール（mail VM）のうち、Terraform が持つもの。中身（Postfix、Dovecot）は ansible/roles/mail ----
# DNS のレコード（A、MX）は cloudflare.tf、ポートは nsg.tf

locals {
  # メールボックスを持つユーザー（@ の前）。ansible/group_vars/mail.yml の mail_users と同じものを書く
  mail_users = ["alphajinsei"]
}

# メールのパスワード：Terraform が作って Vault に入れる。mail VM は platform-secret で読み、Dovecot 用のハッシュにする。
# 自分は手元の oci CLI で一度だけ取り出して、メールソフトとパスワード管理のツールに入れる
resource "random_password" "mail" {
  for_each = toset(local.mail_users)

  length           = 32
  override_special = "-_"
}

resource "oci_vault_secret" "mail_password" {
  for_each = toset(local.mail_users)

  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = "mail-${each.key}-password"
  description    = "Mail (IMAP / SMTP submission) password of ${each.key}@${var.domain}"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.mail[each.key].result)
  }
}
