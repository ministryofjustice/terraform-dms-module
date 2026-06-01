resource "aws_kms_key" "dms_test" {
  description         = "KMS key for ${var.name_prefix} Postgres DMS test resources"
  enable_key_rotation = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-kms"
  })
}

resource "aws_kms_alias" "dms_test" {
  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.dms_test.key_id
}
