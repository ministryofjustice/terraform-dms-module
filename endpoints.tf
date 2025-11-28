# DMS Source Endpoint
resource "aws_dms_endpoint" "source" {
  #checkov:skip=CKV_AWS_296: Use AWS managed KMS key
  endpoint_id   = "${var.db}-source"
  endpoint_type = "source"
  engine_name   = var.dms_source.engine_name

  database_name = var.dms_source.sid
  server_name   = local.database_credentials["host"]
  username      = local.database_credentials["username"]
  password      = "${local.database_credentials["oracle_password"]},${local.database_credentials["asm_password"]}"
  port          = local.database_credentials["port"]

  extra_connection_attributes = var.dms_source.extra_connection_attributes

  tags = merge(
    { Name = "${var.db}-source" },
    var.tags
  )
}

# DMS S3 Target Endpoint
resource "aws_dms_s3_endpoint" "s3_target" {
  # checkov:skip=CKV_AWS_298: Use AWS managed KMS key

  endpoint_id                      = "${var.db}-target"
  endpoint_type                    = "target"
  bucket_name                      = aws_s3_bucket.landing.bucket
  service_access_role_arn          = aws_iam_role.dms.arn
  add_column_name                  = var.s3_target_config.add_column_name
  canned_acl_for_objects           = "bucket-owner-full-control"
  cdc_max_batch_interval           = var.s3_target_config.max_batch_interval
  cdc_min_file_size                = var.s3_target_config.min_file_size
  compression_type                 = "GZIP"
  data_format                      = "parquet"
  encoding_type                    = "rle-dictionary"
  encryption_mode                  = "SSE_S3"
  include_op_for_full_load         = true
  parquet_timestamp_in_millisecond = true
  parquet_version                  = "parquet-2-0"
  timestamp_column_name            = var.s3_target_config.timestamp_column_name

  tags = merge(
    { Name = "${var.db}-target" },
    var.tags
  )
}
