locals {
  existing_arns = var.replication_instance_arns == null ? toset([]) : var.replication_instance_arns

  # When null => create exactly one instance with key "create"
  # When set  => create one instance per ARN with key = ARN (stable and unique)
  instances = (
    length(local.existing_arns) > 0
    ? { for arn in local.existing_arns : arn => { arn = arn, mode = "adopt" } }
    : { "create" = { arn = null, mode = "create" } }
  )
}
