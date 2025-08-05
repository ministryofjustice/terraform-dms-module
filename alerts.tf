
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

resource "aws_cloudwatch_event_rule" "dms_events" {
  name        = "${var.db}-dms-events"
  role_arn    = aws_iam_role.eventbridge.arn
  description = "Triggers when there is a change to dms state"
  event_pattern = jsonencode({
    source    = ["aws.dms"],
    resources = local.source_ids
  })
}
