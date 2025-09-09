locals {
  source_ids = compact([
    aws_dms_replication_task.full_load_replication_task.replication_task_arn,
    length(aws_dms_replication_task.cdc_replication_task) > 0 ? aws_dms_replication_task.cdc_replication_task[0].replication_task_arn : null
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
resource "aws_cloudwatch_log_group" "eventbridge" {
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
  policy_name     = "eventbridge-log-publishing-policy"
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
