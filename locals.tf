locals {
  use_existing = var.existing_replication_instance_arn != null

  replication_instance_arn = (local.use_existing
    ? var.existing_replication_instance_arn
  : aws_dms_replication_instance.instance[0].replication_instance_arn)
}
