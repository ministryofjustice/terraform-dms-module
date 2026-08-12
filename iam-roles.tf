# IAM Role for DMS VPC Access
#
# AWS DMS looks up the VPC-management role by the EXACT name `dms-vpc-role` (it is an
# account-level singleton, not referenced by ARN for that purpose), so this must be the
# literal name rather than a name_prefix. Because only ONE pipeline per AWS account can
# own the singleton, creation is gated behind `manage_dms_service_roles`. Additional
# pipelines in the same account (or accounts where the roles are managed elsewhere) set
# it to false, and the role is looked up by name for the S3 endpoint service-access role.
resource "aws_iam_role" "dms" {
  count = var.manage_dms_service_roles ? 1 : 0
  # This has to be a specific name for some reason see https://repost.aws/questions/QU61eADUU7SnO-t7MmhxgfPA/dms-service-roles
  name = "dms-vpc-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "dms.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    { Name = "dms-vpc-role" },
    var.tags
  )
}

# When this module does not manage the singleton roles, look up the existing
# `dms-vpc-role` so the S3 endpoint service-access role ARN still resolves.
data "aws_iam_role" "dms_vpc" {
  count = var.manage_dms_service_roles ? 0 : 1
  name  = "dms-vpc-role"
}

locals {
  dms_vpc_role_arn  = var.manage_dms_service_roles ? aws_iam_role.dms[0].arn : data.aws_iam_role.dms_vpc[0].arn
  dms_vpc_role_name = var.manage_dms_service_roles ? aws_iam_role.dms[0].name : data.aws_iam_role.dms_vpc[0].name
}

resource "aws_iam_role_policy" "dms" {
  name = "${var.db}-dms"
  role = local.dms_vpc_role_name

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Action" : [
          "s3:ListBucket"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.landing.bucket}",
        "Sid" : "AllowListBucket"
      },
      {
        "Action" : [
          "s3:DeleteObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:PutObjectTagging"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.landing.bucket}/*",
        "Sid" : "AllowDeleteAndPutObject"
      },
      {
        "Action" : [
          "secretsmanager:GetSecretValue"
        ],
        "Effect" : "Allow",
        "Resource" : "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.id}:secret:managed_pipelines/${var.environment}/slack_notifications*",
        "Sid" : "AllowGetSecretValue"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dms-vpc-role-AmazonDMSVPCManagementRole" {
  count      = var.manage_dms_service_roles ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
  role       = aws_iam_role.dms[0].name

  # It takes some time for these attachments to work, and creating the aws_dms_replication_subnet_group fails if this attachment hasn't completed.
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# IAM Role for DMS Cloudwatch Access
#
# Like dms-vpc-role, AWS DMS looks this up by the exact name `dms-cloudwatch-logs-role`,
# so it is an account-level singleton gated behind `manage_dms_service_roles`.
resource "aws_iam_role" "dms_cloudwatch" {
  count = var.manage_dms_service_roles ? 1 : 0
  # This has to be a specific name for some reason
  name = "dms-cloudwatch-logs-role"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "dms.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    { Name = "dms-cloudwatch-logs-role" },
    var.tags
  )
}

resource "aws_iam_role_policy_attachment" "dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole" {
  count      = var.manage_dms_service_roles ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
  role       = aws_iam_role.dms_cloudwatch[0].name
}

# IAM Role for DMS Premigration Assessmeent
resource "aws_iam_role" "dms_premigration" {
  count       = var.create_premigration_assessment_resources ? 1 : 0
  name_prefix = "dms-premigration-assessment-role-"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "dms.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    { Name = "dms-premigration-assessment-role" },
    var.tags
  )
}


resource "aws_iam_role_policy" "dms_premigration" {
  count = var.create_premigration_assessment_resources ? 1 : 0
  name  = "${var.db}-dms-premigration"
  role  = aws_iam_role.dms_premigration[0].id

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:PutObjectTagging"
        ],
        "Resource" : [
          "${aws_s3_bucket.premigration_assessment[0].arn}/*"
        ]
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          aws_s3_bucket.premigration_assessment[0].arn
        ]
      }
    ]
  })
}

resource "aws_iam_role" "eventbridge" {
  name = "${var.db}-eventbridge"
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "events.amazonaws.com"
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {
          "StringEquals" : {
            "aws:SourceAccount" : data.aws_caller_identity.current.id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_sns_publish" {
  name = "${var.db}-eventbridge-sns-publish"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sns:Publish",
        Resource = aws_sns_topic.dms_events.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_cloudwatch_publish" {
  name = "${var.db}-eventbridge-cloudwatch-publish"
  role = aws_iam_role.eventbridge.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream"
        ]
        Resource = "${aws_cloudwatch_log_group.eventbridge.arn}:*"
      }
    ]
  })
}
