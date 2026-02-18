import {
  for_each = { for arn in local.existing_arns : arn => arn }

  to = aws_dms_replication_instance.instance[each.key]
  id = each.value
}
