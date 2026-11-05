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

# ---- 送信：外への配送は OCI Email Delivery に中継する（OCI は外へ出る 25番を塞いでいる） ----
# Postfix が [smtp.email.<region>.oci.oraclecloud.com]:587 に SMTP の資格情報でログインして渡す。
# Email Delivery は、承認済みの差出人（From:）だけを受け、DKIM で署名し、封筒の差出人を bounce.<domain> にして送る

locals {
  mail_relay_host = "smtp.email.${var.region}.oci.oraclecloud.com"
}

# 送信するドメイン。DKIM とカスタム Return-Path はこれにぶら下がる
resource "oci_email_email_domain" "main" {
  compartment_id = var.compartment_id
  name           = var.domain
}

# DKIM：Email Delivery が鍵を作り、d=<domain> で署名する。公開鍵は CNAME で Email Delivery 側を指す（cloudflare.tf）。
# セレクターは <接頭辞>-<リージョンの略>-<日付>（鍵を替えるときは、日付を変えた新しいものを足してから古いものを消す）
resource "oci_email_dkim" "main" {
  email_domain_id = oci_email_email_domain.main.id
  name            = "oci-nrt-20261105"
}

# カスタム Return-Path：封筒の差出人を bounce.<domain> にする。SPF がこの名前で通り、From: と親ドメインが一致する（DMARC）。
# DKIM が Active（Oracle が DNS の CNAME を確かめた）でないと作れない。Terraform はそこまで待てないので、
# 一から作るときは apply が2回になる（1回目はここで失敗する。DKIM が Active になってからもう一度 apply）
resource "oci_email_email_return_path" "main" {
  depends_on = [cloudflare_dns_record.dkim]

  parent_resource_id = oci_email_email_domain.main.id
  name               = "bounce.${var.domain}"
}

# 承認済みの差出人：From: がこのアドレスのメールだけを送れる（それ以外は Email Delivery が拒否する）
resource "oci_email_sender" "user" {
  for_each = toset(local.mail_users)

  compartment_id = var.compartment_id
  email_address  = "${each.key}@${var.domain}"
}

# 中継のための IAM のユーザー。人は使わない。できるのは、承認済みの差出人で送ることだけ
resource "oci_identity_user" "mail_relay" {
  compartment_id = var.tenancy_id
  name           = "mail-relay"
  description    = "Postfix on the mail VM logs in to Email Delivery (SMTP) as this user"
  # Identity Domains のユーザーは主メールアドレスが必須（通知が届くことがある）
  email = "postmaster@${var.domain}"
}

resource "oci_identity_group" "mail_relay" {
  compartment_id = var.tenancy_id
  name           = "mail-relay"
  description    = "May send mail through Email Delivery"
}

resource "oci_identity_user_group_membership" "mail_relay" {
  user_id  = oci_identity_user.mail_relay.id
  group_id = oci_identity_group.mail_relay.id
}

resource "oci_identity_policy" "mail_relay" {
  compartment_id = var.compartment_id
  name           = "mail-relay"
  description    = "Send mail with approved senders in the oci-platform compartment"
  statements = [
    "Allow group ${oci_identity_group.mail_relay.name} to use approved-senders in compartment id ${var.compartment_id}",
  ]
}

# SMTP の資格情報（ユーザー名とパスワード）。パスワードは作ったときにしか返らないので、Vault に入れる。
# ユーザー名は秘密ではない（出力に出す）
resource "oci_identity_smtp_credential" "mail_relay" {
  user_id     = oci_identity_user.mail_relay.id
  description = "Postfix relay on the mail VM"
}

resource "oci_vault_secret" "mail_relay_password" {
  compartment_id = var.compartment_id
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.main.id
  secret_name    = "mail-relay-smtp-password"
  description    = "SMTP credential password of IAM user mail-relay (Email Delivery)"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(oci_identity_smtp_credential.mail_relay.password)
  }
}

# Ansible（roles/mail）が読む
output "mail_relay" {
  value = {
    host          = local.mail_relay_host
    port          = 587
    username      = oci_identity_smtp_credential.mail_relay.username
    password_name = oci_vault_secret.mail_relay_password.secret_name
  }
}
