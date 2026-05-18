locals {
  validation_queue_name = "${var.db}-validation"
}

# Customer-managed KMS key for the validation SQS queues.
# S3 bucket notifications cannot reliably publish to queues encrypted with
# alias/aws/sqs because the AWS-managed key policy cannot be updated to allow
# the s3.amazonaws.com service principal.
resource "aws_kms_key" "validation_sqs" {
  description         = "KMS key for ${local.validation_queue_name} SQS queues"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.validation_sqs_kms.json

  tags = var.tags
}

resource "aws_kms_alias" "validation_sqs" {
  name          = "alias/${local.validation_queue_name}-sqs"
  target_key_id = aws_kms_key.validation_sqs.key_id
}

data "aws_iam_policy_document" "validation_sqs_kms" {
  statement {
    sid    = "AllowAccountRootFullAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowS3ToUseKeyForQueueNotifications"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.landing.arn]
    }
  }

  statement {
    sid    = "AllowValidationLambdaToDecryptQueueMessages"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [module.validation_lambda_function.lambda_role_arn]
    }

    actions = [
      "kms:Decrypt",
    ]

    resources = ["*"]
  }
}

# Dead-letter queue for messages that fail processing repeatedly.
# DMS landing events that fail validation Lambda processing will land here
# after the configured maxReceiveCount, allowing redrive once the underlying
# issue is fixed.
resource "aws_sqs_queue" "validation_dlq" {
  name                              = "${local.validation_queue_name}-dlq"
  message_retention_seconds         = 1209600 # 14 days (max)
  kms_master_key_id                 = aws_kms_key.validation_sqs.arn
  kms_data_key_reuse_period_seconds = 300

  tags = var.tags
}

# Main queue receiving S3 ObjectCreated events from the landing bucket.
# Lambda event source mapping consumes from this queue and invokes
# the validation Lambda with batched messages.
resource "aws_sqs_queue" "validation" {
  name                              = local.validation_queue_name
  visibility_timeout_seconds        = 360    # 6x Lambda timeout (60s) per AWS guidance
  message_retention_seconds         = 345600 # 4 days
  kms_master_key_id                 = aws_kms_key.validation_sqs.arn
  kms_data_key_reuse_period_seconds = 300

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.validation_dlq.arn
    maxReceiveCount     = 5
  })

  tags = var.tags
}

# Allow the landing S3 bucket to send messages to the validation queue.
data "aws_iam_policy_document" "validation_queue" {
  statement {
    sid     = "AllowS3LandingBucket"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    resources = [aws_sqs_queue.validation.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.landing.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sqs_queue_policy" "validation" {
  queue_url = aws_sqs_queue.validation.id
  policy    = data.aws_iam_policy_document.validation_queue.json
}

# IAM permissions for the validation Lambda to consume from the queue.
data "aws_iam_policy_document" "validation_lambda_sqs" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]

    resources = [aws_sqs_queue.validation.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
    ]

    resources = [aws_kms_key.validation_sqs.arn]
  }
}

resource "aws_iam_role_policy" "validation_lambda_sqs" {
  name   = "${var.db}-validation-sqs"
  role   = module.validation_lambda_function.lambda_role_name
  policy = data.aws_iam_policy_document.validation_lambda_sqs.json
}

# Wire the queue to the Lambda. ReportBatchItemFailures lets us return
# partial-batch failures so SQS only retries the messages that actually
# failed, instead of redelivering the whole batch.
resource "aws_lambda_event_source_mapping" "validation" {
  event_source_arn                   = aws_sqs_queue.validation.arn
  function_name                      = module.validation_lambda_function.lambda_function_arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# Alarm on DLQ depth: anything > 0 means a Parquet file failed validation
# processing 5 times and needs investigation/redrive.
resource "aws_cloudwatch_metric_alarm" "validation_dlq_depth" {
  alarm_name          = "${var.db}-validation-dlq-depth"
  alarm_description   = "Messages in validation DLQ for ${var.db}. Indicates Parquet files that failed validation Lambda processing 5 times."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.validation_dlq.name
  }

  alarm_actions = [aws_sns_topic.dms_events.arn]
  ok_actions    = [aws_sns_topic.dms_events.arn]

  tags = var.tags
}
