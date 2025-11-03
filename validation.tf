# Policy document to allow write access to the raw_history, invalid_data buckets, read access to the validation_metadata bucket
# and read/delete access to the landing bucket
data "aws_iam_policy_document" "validation_lambda_function" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${local.raw_history_bucket_id}/*",
      "${aws_s3_bucket.invalid.arn}/*",
    ]
  }

  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject"
    ]

    resources = [
      aws_s3_bucket.validation_metadata.arn,
      "${aws_s3_bucket.validation_metadata.arn}/*"
    ]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.landing.arn,
      "${aws_s3_bucket.landing.arn}/*"
    ]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      var.slack_webhook_secret_id
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
}

module "validation_lambda_function" {
  # Commit hash for v7.20.1
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-lambda?ref=84dfbfddf9483bc56afa0aff516177c03652f0c7"

  function_name           = "${var.db}-validation"
  description             = "Lambda to validate DMS data output"
  handler                 = "main.handler"
  runtime                 = "python3.12"
  timeout                 = 60
  architectures           = ["x86_64"]
  build_in_docker         = false
  store_on_s3             = true
  s3_bucket               = aws_s3_bucket.lambda.bucket
  s3_object_storage_class = "STANDARD"
  s3_prefix               = "validation/"
  tracing_mode           = "Active"
  attach_tracing_policy    = true

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.validation_lambda_function.json

  environment_variables = {
    ENVIRONMENT         = var.environment
    PASS_BUCKET         = local.raw_history_bucket_id
    FAIL_BUCKET         = aws_s3_bucket.invalid.bucket
    METADATA_BUCKET     = aws_s3_bucket.validation_metadata.bucket
    METADATA_PATH       = ""
    SLACK_SECRET_ARN    = var.slack_webhook_secret_id
    VALID_FILES_MUTABLE = var.valid_files_mutable
    OUTPUT_KEY_PREFIX   = var.output_key_prefix
    OUTPUT_KEY_SUFFIX   = var.output_key_suffix
  }

  source_path = [{
    path = "${path.module}/lambda-functions/validation/"
    # Exclude tests and dist-info directories from the deployment package
    commands = [
      "pip3.12 install --platform=manylinux2014_x86_64 --only-binary=:all: --no-compile --target=. -r requirements.txt",
      "rm -rf pyarrow/tests numpy/tests *.dist-info", # Exclude tests and dist-info directories from the deployment package
      ":zip",
    ]

  }]

  tags = var.tags
}
