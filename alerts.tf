
locals {
  source_ids = compact([
    aws_dms_replication_task.full_load_replication_task.replication_task_id,
    length(aws_dms_replication_task.cdc_replication_task) > 0 ? aws_dms_replication_task.cdc_replication_task[0].replication_task_id : null
  ])
}

resource "aws_sns_topic" "dms_events" {
  name              = "${var.db}-dms"
  kms_master_key_id = var.dms_replication_instance.kms_key_arn
}

resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.dms_events.arn
  protocol  = "https"
  endpoint  = data.aws_secretsmanager_secret_version.slack_webhook.secret_string
}

resource "aws_dms_event_subscription" "task" {
  enabled          = true
  event_categories = []
  name             = "${var.db}-task"
  sns_topic_arn    = aws_sns_topic.dms_events.arn
  source_ids       = local.source_ids
  source_type      = "replication-task"

  tags = var.tags
}

resource "aws_dms_event_subscription" "instance" {
  enabled          = true
  event_categories = []
  name             = "${var.db}-instance"
  sns_topic_arn    = aws_sns_topic.dms_events.arn
  source_ids       = [aws_dms_replication_instance.instance.replication_instance_id]
  source_type      = "replication-instance"

  tags = var.tags
}