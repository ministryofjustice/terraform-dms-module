resource "aws_kms_key" "dms_test" {
  description             = "KMS key for ${var.name_prefix} Postgres DMS test resources"
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
    Name = "${var.name_prefix}-kms"
  })
}

resource "aws_kms_alias" "dms_test" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.dms_test.key_id
}
