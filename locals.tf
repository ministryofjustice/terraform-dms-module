locals {
  adopt = var.existing_replication_instance_arn != null

  # Deterministic key for the managed resource address
  instance_key = local.adopt ? "adopt" : "create"

  # for_each map: always exactly one instance, but keyed differently by mode
  instances = {
    (local.instance_key) = {
      existing_arn = var.existing_replication_instance_arn
      mode         = local.adopt ? "adopt" : "create"
    }
  }
}
