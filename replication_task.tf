data "aws_s3_object" "full_load_mapping_rules" {
  for_each = var.full_load_jobs
  bucket   = each.value.mapping_rules.bucket
  key      = each.value.mapping_rules.key
}

data "aws_s3_object" "cdc_mapping_rules" {
  for_each = var.cdc_jobs
  bucket   = each.value.mapping_rules.bucket
  key      = each.value.mapping_rules.key
}

resource "aws_dms_replication_task" "full_load_replication_task" {
  for_each = var.full_load_jobs

  replication_task_id      = each.value.replication_task_id
  migration_type           = "full-load"
  replication_instance_arn = local.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_s3_endpoint.s3_target.endpoint_arn

  table_mappings = data.aws_s3_object.full_load_mapping_rules[each.key].body

  tags = merge(var.tags, { Name = each.value.replication_task_id, job = each.key })
}

resource "aws_dms_replication_task" "cdc_replication_task" {
  for_each = var.cdc_jobs

  replication_task_id      = each.value.replication_task_id
  migration_type           = "cdc"
  replication_instance_arn = local.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_s3_endpoint.s3_target.endpoint_arn

  cdc_start_time = each.value.cdc_start_time
  table_mappings = data.aws_s3_object.cdc_mapping_rules[each.key].body

  tags = merge(var.tags, { Name = each.value.replication_task_id, job = each.key })
}
