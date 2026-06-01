# -----------------------------------------------------------------------------
# Use the existing MP shared VPC, subnets, and create a KMS key
# VPC and subnets are provisioned by the Modernisation Platform core-vpc pipeline
# -----------------------------------------------------------------------------

# --- Shared VPC (owned by MP core account, shared via RAM) ---

data "aws_vpc" "shared" {
  tags = {
    Name = "laa-development"
  }
}

data "aws_subnets" "data" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }

  filter {
    name   = "tag:Name"
    values = ["laa-development-general-data-*"]
  }
}

# --- KMS Key ---

resource "aws_kms_key" "dms_test" {
  description             = "KMS key for DMS test rig RDS encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-dms-test"
  })
}

resource "aws_kms_alias" "dms_test" {
  name          = "alias/${var.name_prefix}-dms-test"
  target_key_id = aws_kms_key.dms_test.key_id
}
