
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

resource "aws_cloudwatch_event_rule" "dms_events" {
  name        = "${var.db}-dms-events"
  role_arn    = aws_iam_role.eventbridge.arn
  description = "Triggers on DMS replication task state changes"

  event_pattern = jsonencode({
    source      = ["aws.dms"],
    "detail-type" = ["DMS Replication Task State Change"],
    resources   = local.source_ids
  })
}

resource "aws_cloudwatch_event_target" "dms_to_sns" {
  rule      = aws_cloudwatch_event_rule.dms_events.name
  arn       = aws_sns_topic.dms_events.arn
  target_id = "DMSAlertToSNS"

  input_transformer {
    input_paths = {
      category  = "$.detail.category"
      event     = "$.detail.eventType"
      message   = "$.detail.detailMessage"
      link      = "$.detail.resourceLink"
      taskArn   = "$.resources[0]"
      sourceId  = "$.detail.sourceId"
      time      = "$.time"
    }

    input_template = <<TEMPLATE
{
  "Category": "<category>",
  "Event":    "<event>",
  "TaskArn":  "<taskArn>",
  "SourceId": "<sourceId>",
  "Message":  "<message>",
  "Link":     "<link>",
  "Time":     "<time>"
}
TEMPLATE
  }
}

