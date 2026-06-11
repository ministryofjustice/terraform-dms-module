locals {
  source_ids = flatten([
    [aws_dms_replication_task.full_load_replication_task.replication_task_arn],

    [for _, t in aws_dms_replication_task.independent_full_load_replication_task : t.replication_task_arn],

    length(aws_dms_replication_task.cdc_replication_task) > 0
    ? [aws_dms_replication_task.cdc_replication_task[0].replication_task_arn]
    : []
  ])
}

resource "aws_sns_topic" "dms_events" {
  name              = "${var.db}-dms"
  kms_master_key_id = var.dms_replication_instance.kms_key_arn
}

resource "aws_sns_topic_policy" "dms_events" {
  arn    = aws_sns_topic.dms_events.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    resources = [aws_sns_topic.dms_events.arn]
  }
}

resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.dms_events.arn
  protocol  = "https"
  endpoint  = data.aws_secretsmanager_secret_version.slack_webhook.secret_string
}

# ------------------ Replication Task Events ------------------

resource "aws_cloudwatch_event_rule" "dms_events" {
  name        = "${var.db}-dms-events"
  role_arn    = aws_iam_role.eventbridge.arn
  description = "Triggers on DMS replication task state changes for listed eventIDs"

  event_pattern = jsonencode({
    source        = ["aws.dms"],
    "detail-type" = ["DMS Replication Task State Change"],
    resources     = local.source_ids,
    detail = {
      eventId = [
        "DMS-EVENT-0069",
        "DMS-EVENT-0073",
        "DMS-EVENT-0079",
        "DMS-EVENT-0081",
        "DMS-EVENT-0091",
        "DMS-EVENT-0092",
        "DMS-EVENT-0093"
      ]
    }
  })
}

resource "aws_cloudwatch_event_rule" "dms_events_by_category" {
  name        = "${var.db}-dms-events-by-category"
  role_arn    = aws_iam_role.eventbridge.arn
  description = "Triggers on DMS replication task state changes for listed categories"

  event_pattern = jsonencode({
    source        = ["aws.dms"],
    "detail-type" = ["DMS Replication Task State Change"],
    resources     = local.source_ids,
    detail = {
      category = [
        "Creation",
        "ConfigurationChange",
        "Failure"
      ]
    }
  })
}

resource "aws_cloudwatch_event_target" "dms_to_sns" {
  rule      = aws_cloudwatch_event_rule.dms_events.name
  arn       = aws_sns_topic.dms_events.arn
  target_id = "DMSAlertToSNS"

  input_transformer {
    input_paths = {
      category = "$.detail.category"
      event    = "$.detail.eventType"
      message  = "$.detail.detailMessage"
      taskArn  = "$.resources[0]"
      time     = "$.time"
    }

    input_template = <<TEMPLATE
{
  "SourceDB": "${var.db}",
  "Category": "<category>",
  "Event":    "<event>",
  "TaskArn":  "<taskArn>",
  "Message":  "<message>",
  "Time":     "<time>"
}
TEMPLATE
  }
}

resource "aws_cloudwatch_event_target" "dms_to_sns_by_category" {
  rule      = aws_cloudwatch_event_rule.dms_events_by_category.name
  arn       = aws_sns_topic.dms_events.arn
  target_id = "DMSAlertToSNS"

  input_transformer {
    input_paths = {
      category = "$.detail.category"
      event    = "$.detail.eventType"
      message  = "$.detail.detailMessage"
      taskArn  = "$.resources[0]"
      time     = "$.time"
    }

    input_template = <<TEMPLATE
{
  "SourceDB": "${var.db}",
  "Category": "<category>",
  "Event":    "<event>",
  "TaskArn":  "<taskArn>",
  "Message":  "<message>",
  "Time":     "<time>"
}
TEMPLATE
  }
}

# ------------------ Replication Instance Events ------------------

resource "aws_cloudwatch_event_rule" "dms_instance_events" {
  name        = "${var.db}-dms-instance-events"
  role_arn    = aws_iam_role.eventbridge.arn
  description = "Triggers on DMS replication instance state changes"

  event_pattern = jsonencode({
    source        = ["aws.dms"],
    "detail-type" = ["DMS Replication Instance State Change"],
    resources     = [aws_dms_replication_instance.instance.replication_instance_arn],
  })
}

resource "aws_cloudwatch_event_target" "dms_instance_to_sns" {
  rule      = aws_cloudwatch_event_rule.dms_instance_events.name
  arn       = aws_sns_topic.dms_events.arn
  target_id = "DMSInstanceAlertToSNS"

  input_transformer {
    input_paths = {
      category    = "$.detail.category"
      event       = "$.detail.eventType"
      message     = "$.detail.detailMessage"
      instanceArn = "$.resources[0]"
      link        = "$.detail.resourceLink"
      time        = "$.time"
    }

    input_template = <<TEMPLATE
{
  "SourceDB": "${var.db}",
  "Category": "<category>",
  "Event":    "<event>",
  "InstanceArn": "<instanceArn>",
  "Message":  "<message>",
  "Time":     "<time>",
  "Link":     "<link>"
}
TEMPLATE
  }
}

# ------------------ EventBridge CloudWatch Logs ------------------
#trivy:ignore:AVD-AWS-0017 CMK not used here
resource "aws_cloudwatch_log_group" "eventbridge" {
  #checkov:skip=CKV_AWS_158: kms not used here
  name = "${var.db}-events-logs"

  log_group_class   = "STANDARD"
  retention_in_days = 0
  tags              = var.tags
}

data "aws_iam_policy_document" "eventbridge" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    principals {
      type = "Service"
      identifiers = [
        "events.amazonaws.com",
        "delivery.logs.amazonaws.com"
      ]
    }
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:log-group:${aws_cloudwatch_log_group.eventbridge.name}:*"
    ]
  }
}

resource "aws_cloudwatch_log_resource_policy" "eventbridge" {
  policy_document = data.aws_iam_policy_document.eventbridge.json
  policy_name     = "eventbridge-log-publishing-policy-${var.db}"
}

resource "aws_cloudwatch_event_target" "eventbridge_dms_events" {
  rule = aws_cloudwatch_event_rule.dms_events.name
  arn  = aws_cloudwatch_log_group.eventbridge.arn
}

resource "aws_cloudwatch_event_target" "eventbridge_dms_events_by_category" {
  rule = aws_cloudwatch_event_rule.dms_events_by_category.name
  arn  = aws_cloudwatch_log_group.eventbridge.arn
}

resource "aws_cloudwatch_event_target" "eventbridge_dms_instance_events" {
  rule = aws_cloudwatch_event_rule.dms_instance_events.name
  arn  = aws_cloudwatch_log_group.eventbridge.arn
}

# ------------------ Postgres Source RDS — Replication Slot Alarms ------------------
# These alarms protect against orphaned/stuck logical replication slots pinning WAL
# on the source Postgres RDS, which will eventually fill the disk. They are only
# created when engine_name == "postgres" and a source RDS instance id is supplied.

locals {
  enable_postgres_slot_alarms = var.dms_source.engine_name == "postgres" && var.source_rds_instance_id != null
}

resource "aws_cloudwatch_metric_alarm" "postgres_replication_slot_lag" {
  count = local.enable_postgres_slot_alarms ? 1 : 0

  alarm_name          = "${var.db}-postgres-replication-slot-lag"
  alarm_description   = "WAL bytes pinned by the oldest logical replication slot on ${var.source_rds_instance_id}. A persistently high value indicates an orphaned or stuck DMS replication slot that will fill the source disk."
  namespace           = "AWS/RDS"
  metric_name         = "OldestReplicationSlotLag"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.postgres_replication_slot_lag_threshold_bytes
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.source_rds_instance_id
  }

  alarm_actions = [aws_sns_topic.dms_events.arn]
  ok_actions    = [aws_sns_topic.dms_events.arn]

  tags = merge(
    { Name = "${var.db}-postgres-replication-slot-lag" },
    var.tags
  )
}

resource "aws_cloudwatch_metric_alarm" "postgres_transaction_logs_disk_usage" {
  count = local.enable_postgres_slot_alarms ? 1 : 0

  alarm_name          = "${var.db}-postgres-transaction-logs-disk-usage"
  alarm_description   = "WAL disk usage on ${var.source_rds_instance_id}. Sustained growth alongside replication-slot lag indicates WAL is being retained by a stuck slot."
  namespace           = "AWS/RDS"
  metric_name         = "TransactionLogsDiskUsage"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.postgres_transaction_logs_disk_usage_threshold_bytes
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.source_rds_instance_id
  }

  alarm_actions = [aws_sns_topic.dms_events.arn]
  ok_actions    = [aws_sns_topic.dms_events.arn]

  tags = merge(
    { Name = "${var.db}-postgres-transaction-logs-disk-usage" },
    var.tags
  )
}
