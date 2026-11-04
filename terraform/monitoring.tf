# ---- 監視：止まったことだけを知る（アラームは2つ）。通知はメール ----
# CPU やメモリの高騰は見ない。Always Free で拡張の余力がなく、鳴っても打つ手がないため。
# HeatWave も見ない（マネージドに任せる。アプリの /health は DB を見ないので、DB が落ちても鳴らない）

resource "oci_ons_notification_topic" "alerts" {
  compartment_id = var.compartment_id
  name           = "platform-alerts"
  description    = "Alarms of oci-platform"
}

# 作ると確認メールが届く。リンクを押すまで通知は届かない
resource "oci_ons_subscription" "email" {
  compartment_id = var.compartment_id
  topic_id       = oci_ons_notification_topic.alerts.id
  protocol       = "EMAIL"
  endpoint       = var.alert_email
}

# アプリ（コンテナ）が止まった：どれかのバックエンド・セットに異常なバックエンドがある。
# バックエンド・セットごとに判定するので、アプリを足してもこの1つで見られる（アプリ側は何も足さない）。
# デプロイの入れ替え（数秒）で鳴らないように、3分続いたら発報する
resource "oci_monitoring_alarm" "backend_down" {
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "platform-backend-down"
  namespace             = "oci_lbaas"
  query                 = "unhealthyBackendServers[1m].groupBy(backendSetName).max() > 0"
  pending_duration      = "PT3M"
  severity              = "CRITICAL"
  body                  = "A backend set of the LB has an unhealthy backend (the app is down). On oci-app: cd /opt/apps/<name> && docker compose ps && docker compose logs app"
  destinations          = [oci_ons_notification_topic.alerts.id]
  is_enabled            = true

  # バックエンド・セット（アプリ）ごとに別のメールにする
  is_notifications_per_metric_dimension_enabled = true
}

# VM が止まった：Oracle Cloud Agent の CPU のメトリクスが10分届かない。
# 閾値のアラームは、VM が止まるとデータがなくなって何も言わなくなるので、「無いこと」で検知する
resource "oci_monitoring_alarm" "vm_down" {
  compartment_id        = var.compartment_id
  metric_compartment_id = var.compartment_id
  display_name          = "platform-vm-down"
  namespace             = "oci_computeagent"
  query                 = "CpuUtilization[1m].groupBy(resourceDisplayName).absent(10m)"
  severity              = "CRITICAL"
  body                  = "A VM stopped sending metrics (stopped, hung, or Oracle Cloud Agent is down). Check the instance in the console."
  destinations          = [oci_ons_notification_topic.alerts.id]
  is_enabled            = true

  is_notifications_per_metric_dimension_enabled = true
}

# ---- ログ：LB のアクセスログとエラーログを OCI Logging に入れる（サービス・ログ。エージェントは要らない） ----
# コンテナのログは送らない。app で docker compose logs を見る

resource "oci_logging_log_group" "platform" {
  compartment_id = var.compartment_id
  display_name   = "platform"
}

# LB は一度に1つの変更しか受け付けないので、2つのログは順番に作る
resource "oci_logging_log" "lb_access" {
  log_group_id       = oci_logging_log_group.platform.id
  display_name       = "lb-access"
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = 30

  configuration {
    compartment_id = var.compartment_id
    source {
      source_type = "OCISERVICE"
      service     = "loadbalancer"
      resource    = oci_load_balancer_load_balancer.main.id
      category    = "access"
    }
  }
}

resource "oci_logging_log" "lb_error" {
  depends_on = [oci_logging_log.lb_access]

  log_group_id       = oci_logging_log_group.platform.id
  display_name       = "lb-error"
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = 30

  configuration {
    compartment_id = var.compartment_id
    source {
      source_type = "OCISERVICE"
      service     = "loadbalancer"
      resource    = oci_load_balancer_load_balancer.main.id
      category    = "error"
    }
  }
}
