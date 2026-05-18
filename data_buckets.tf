locals {
  raw_history_bucket_id = length(var.output_bucket) > 0 ? var.output_bucket : aws_s3_bucket.raw_history[0].id
}

# S3 bucket to store lambda code/packages
#trivy:ignore:AVD-AWS-0089 No logging required
#trivy:ignore:s3-bucket-logging No logging required
resource "aws_s3_bucket" "lambda" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  bucket_prefix = "${var.db}-lambda-functions-"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "lambda" {
  bucket = aws_s3_bucket.lambda.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "lambda" {
  bucket = aws_s3_bucket.lambda.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "lambda" {
  bucket = aws_s3_bucket.lambda.id
  versioning_configuration {
    status = "Enabled"
  }
}


# S3 bucket - Landing
#trivy:ignore:AVD-AWS-0089 No logging required
#trivy:ignore:s3-bucket-logging No logging required
resource "aws_s3_bucket" "landing" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  bucket_prefix = "${var.db}-landing-"
}

resource "aws_s3_bucket_ownership_controls" "landing" {
  bucket = aws_s3_bucket.landing.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "landing" {
  bucket = aws_s3_bucket.landing.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0090 Versioning not needed
resource "aws_s3_bucket_versioning" "landing" {
  bucket = aws_s3_bucket.landing.id
  versioning_configuration {
    status = "Disabled"
  }
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "landing" {
  bucket = aws_s3_bucket.landing.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 bucket notification to enqueue object-created events for the
# validation Lambda. Using SQS in front of Lambda gives us configurable
# retry, backpressure during DMS bursts, a DLQ for poison messages, and
# the ability to redrive after fixing root causes.
resource "aws_s3_bucket_notification" "landing" {
  bucket = aws_s3_bucket.landing.bucket

  queue {
    queue_arn = aws_sqs_queue.validation.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [
    aws_sqs_queue_policy.validation,
    aws_kms_key.validation_sqs,
  ]
}

# Bucket to store validated data
# This can be passed in from outside the module
# but in that case it is assumed all related aws_s3_bucket_* resources are being managed externally
# Local to determine the actual bucket name to use
#trivy:ignore:AVD-AWS-0089 No logging required
#trivy:ignore:s3-bucket-logging No logging required
resource "aws_s3_bucket" "raw_history" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  count         = length(var.output_bucket) > 0 ? 0 : 1
  bucket_prefix = "${var.db}-raw-history-"
}

# Only apply controls when we create the bucket
resource "aws_s3_bucket_ownership_controls" "raw_history" {
  count  = length(var.output_bucket) > 0 ? 0 : 1
  bucket = aws_s3_bucket.raw_history[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "raw_history" {
  count  = length(var.output_bucket) > 0 ? 0 : 1
  bucket = aws_s3_bucket.raw_history[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0090 Versioning not needed
resource "aws_s3_bucket_versioning" "raw_history" {
  count  = length(var.output_bucket) > 0 ? 0 : 1
  bucket = aws_s3_bucket.raw_history[0].id
  versioning_configuration {
    status = "Disabled"
  }
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_history" {
  count  = length(var.output_bucket) > 0 ? 0 : 1
  bucket = aws_s3_bucket.raw_history[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Invalid bucket
#trivy:ignore:AVD-AWS-0089 No logging required
#trivy:ignore:s3-bucket-logging No logging required
resource "aws_s3_bucket" "invalid" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  bucket_prefix = "${var.db}-invalid-"
}

resource "aws_s3_bucket_ownership_controls" "invalid" {
  bucket = aws_s3_bucket.invalid.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "invalid" {
  bucket = aws_s3_bucket.invalid.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0090 Versioning not needed
resource "aws_s3_bucket_versioning" "invalid" {
  bucket = aws_s3_bucket.invalid.id
  versioning_configuration {
    status = "Disabled"
  }
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "invalid" {
  bucket = aws_s3_bucket.invalid.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket to store premigration-assessment
#trivy:ignore:AVD-AWS-0089 No logging required
#trivy:ignore:s3-bucket-logging No logging required
resource "aws_s3_bucket" "premigration_assessment" {
  #checkov:skip=CKV2_AWS_62: no notification argument
  #checkov:skip=CKV_AWS_18: no event notification argument
  #checkov:skip=CKV_AWS_144: cross region replication not a thing
  #checkov:skip=CKV_AWS_21: bucket versioning argument deprecated
  #checkov:skip=CKV2_AWS_61: no lifecycle rules
  #checkov:skip=CKV_AWS_145: not using kms here
  count         = var.create_premigration_assessment_resources ? 1 : 0
  bucket_prefix = "${var.db}-pma-"
}

resource "aws_s3_bucket_ownership_controls" "premigration_assessment" {
  count  = var.create_premigration_assessment_resources ? 1 : 0
  bucket = aws_s3_bucket.premigration_assessment[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "premigration_assessment" {
  count  = var.create_premigration_assessment_resources ? 1 : 0
  bucket = aws_s3_bucket.premigration_assessment[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

#trivy:ignore:AVD-AWS-0090 Versioning not needed
resource "aws_s3_bucket_versioning" "premigration_assessment" {
  count  = var.create_premigration_assessment_resources ? 1 : 0
  bucket = aws_s3_bucket.premigration_assessment[0].id
  versioning_configuration {
    status = "Disabled"
  }
}

#trivy:ignore:AVD-AWS-0132 Uses AES256 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "premigration_assessment" {
  count  = var.create_premigration_assessment_resources ? 1 : 0
  bucket = aws_s3_bucket.premigration_assessment[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
