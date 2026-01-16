#S3 bucket to store source metadata
#trivy:ignore:AVD-AWS-0089 No logging required
resource "aws_s3_bucket" "validation_metadata" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  bucket_prefix = "${var.db}-metadata-"

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "validation_metadata" {
  bucket = aws_s3_bucket.validation_metadata.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "validation_metadata" {
  bucket = aws_s3_bucket.validation_metadata.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0090 Versioning not needed
resource "aws_s3_bucket_versioning" "validation_metadata" {
  bucket = aws_s3_bucket.validation_metadata.id
  versioning_configuration {
    status = "Enabled"
  }
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "validation_metadata" {
  bucket = aws_s3_bucket.validation_metadata.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


data "aws_iam_policy_document" "metadata_generator_lambda_function" {
  # Lambda can upload files to the metadata bucket
  statement {
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.validation_metadata.arn,
      "${aws_s3_bucket.validation_metadata.arn}/*",
    ]
  }

  # Lambda can reprocess data in the invalid bucket
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.invalid.arn,
      "${aws_s3_bucket.invalid.arn}/*"
    ]
  }

  # Lambda can access configuration files placed in its own bucket
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      aws_s3_bucket.lambda.arn,
      "${aws_s3_bucket.lambda.arn}/*"
    ]
  }

  # Lambda can pull mappings json file
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${var.dms_mapping_rules.bucket}",
      "arn:aws:s3:::${var.dms_mapping_rules.bucket}/*",
    ]
  }

  # Lambda can reprocess data in the invalid bucket
  statement {
    actions = [
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.landing.arn,
      "${aws_s3_bucket.landing.arn}/*"
    ]
  }

  # Lambda can get the secret value for the data source from AWS Secrets Manager
  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      var.dms_source.secrets_manager_arn
    ]
  }

  # Lambda needs permissions on the KMS key to access the above secret
  statement {
    actions = [
      "kms:DescribeKey",
      "kms:Decrypt"
    ]
    resources = [
      var.dms_source.secrets_manager_kms_arn
    ]
    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${data.aws_region.current.name}.amazonaws.com",
      ]
    }
  }

  # Lambda can create glue database/table
  # checkov:skip=CKV_AWS_111: The resource is not publicly accessible
  # checkov:skip=CKV_AWS_356: Required glue permissions for the lambda
  statement {
    actions = [
      "glue:GetDatabase",
      "glue:CreateDatabase",
      "glue:GetTable",
      "glue:CreateTable",
      "glue:UpdateTable",
    ]

    resources = [
      var.glue_catalog_arn,
      "${trimsuffix(var.glue_catalog_arn, ":catalog")}:database/${local.database_credentials["dbInstanceIdentifier"]}",
      "${trimsuffix(var.glue_catalog_arn, ":catalog")}:table/${local.database_credentials["dbInstanceIdentifier"]}/*",
    ]
  }

  # Lambda can assume sts role
  statement {
    actions = [
      "sts:TagSession",
      "sts:AssumeRole"
    ]

    resources = [
      var.glue_catalog_role_arn
    ]
  }
}

# Create security group for Lambda function
#trivy:ignore:AVD-AWS-0104 Allow all egress traffic
resource "aws_security_group" "metadata_generator_lambda_function" {
  #checkov:skip=CKV_AWS_382: Allow all egress traffic
  #checkov:skip=CKV2_AWS_5: Security Groups are attached to another resource
  name        = "${var.db}-metadata-generator-lambda-function"
  vpc_id      = var.vpc_id
  description = "Security group for Lambda function to generate metadata for ${var.db} DMS data output"

  egress {
    description = "Allow all egress traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

#trivy:ignore:AVD-AWS-0066 X-Ray tracing not currently required. Logs sent to CloudWatch.
module "metadata_generator" {
  # Commit hash for v7.20.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-lambda?ref=84dfbfddf9483bc56afa0aff516177c03652f0c7"

  function_name           = "${var.db}-metadata-generator"
  description             = "Lambda to generate metadata for ${var.db} DMS data output"
  handler                 = "main.handler"
  runtime                 = "python3.12"
  memory_size             = 4096
  timeout                 = 900
  architectures           = ["x86_64"]
  build_in_docker         = false
  store_on_s3             = true
  s3_bucket               = aws_s3_bucket.lambda.bucket
  s3_object_storage_class = "STANDARD"
  s3_prefix               = "metadata-generator/"

  # Lambda function will be attached to the VPC to access the source database
  vpc_security_group_ids = [aws_security_group.metadata_generator_lambda_function.id]
  vpc_subnet_ids         = data.aws_subnets.subnet_ids_vpc_subnets.ids
  attach_network_policy  = true


  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.metadata_generator_lambda_function.json

  environment_variables = {
    ENVIRONMENT                          = var.environment
    DB_SECRET_ARN                        = var.dms_source.secrets_manager_arn
    METADATA_BUCKET                      = aws_s3_bucket.validation_metadata.bucket
    LANDING_BUCKET                       = aws_s3_bucket.landing.bucket
    INVALID_BUCKET                       = aws_s3_bucket.invalid.bucket
    RAW_HISTORY_BUCKET                   = local.raw_history_bucket_id
    OUTPUT_KEY_PREFIX                    = var.output_key_prefix
    LAMBDA_BUCKET                        = aws_s3_bucket.lambda.bucket
    ENGINE                               = var.dms_source.engine_name
    DATABASE_NAME                        = var.dms_source.sid
    GLUE_CATALOG_ARN                     = var.glue_catalog_arn
    GLUE_CATALOG_ROLE_ARN                = var.glue_catalog_role_arn
    USE_GLUE_CATALOG                     = var.write_metadata_to_glue_catalog
    DMS_MAPPING_RULES_BUCKET             = var.dms_mapping_rules.bucket
    DMS_MAPPING_RULES_KEY                = var.dms_mapping_rules.key
    RETRY_FAILED_AFTER_RECREATE_METADATA = var.retry_failed_after_recreate_metadata
  }

  source_path = [{
    path = "${path.module}/lambda_functions/metadata_generator/"
    commands = [
      "pip3.12 install --platform=manylinux2014_x86_64 --only-binary=:all: --no-compile --target=. -r requirements.txt",
      ":zip",
    ]
  }]

  tags = var.tags
}
