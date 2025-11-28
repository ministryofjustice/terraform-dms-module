resource "aws_kms_key" "dms_source_cmk" {
  description             = "KMS key for DMS endpoints"
  deletion_window_in_days = 30

  tags = merge(
    { Name = "${var.db}-dms-kms-key" },
    var.tags
  )
}