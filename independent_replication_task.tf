

# Local to parse the JSON
data "aws_s3_object" "independent_mapping_rules" {
  for_each = var.independent_full_loads
  bucket   = each.value.path.bucket
  key      = each.value.path.key
}

locals {
  independent_input_data = {
    for full_load_name, full_load in var.independent_full_loads :
    full_load_name => jsondecode(data.aws_s3_object.independent_mapping_rules[full_load_name].body)
  }
  independent_objects            = { for full_load_name, full_load in local.independent_input_data : full_load_name => [for object in full_load.objects : replace(object, "-", "_")] }
  independent_blobs              = { for full_load_name, full_load in local.independent_input_data : full_load_name => full_load.blobs }
  independent_columns_to_exclude = { for full_load_name, full_load in local.independent_input_data : full_load_name => full_load.columns_to_exclude }
  independent_rules = { for full_load_name, full_load in local.independent_input_data : full_load_name => flatten(concat(
    [
      for idx, obj in local.independent_objects[full_load_name] : {
        rule-type   = "selection"
        rule-id     = idx + 1 # Using iteration number (1-based index)
        rule-name   = "include-${lower(obj)}"
        rule-action = "explicit"
        object-locator = {
          schema-name = length(split(".", obj)) > 1 ? split(".", obj)[0] : local.independent_input_data[full_load_name].schema
          table-name  = length(split(".", obj)) > 1 ? split(".", obj)[1] : obj
        }
      }
    ],
    [
      for idx, obj in local.independent_objects[full_load_name] : {
        rule-type   = "transformation"
        rule-id     = length(local.independent_objects[full_load_name]) + idx + 1
        rule-name   = "add-scn-${lower(obj)}"
        rule-action = "add-column"
        rule-target = "column"
        value       = "SCN"
        expression  = "$AR_H_STREAM_POSITION"
        data-type = {
          type   = "string"
          length = 50
        }
        object-locator = {
          schema-name = length(split(".", obj)) > 1 ? split(".", obj)[0] : local.independent_input_data[full_load_name].schema
          table-name  = length(split(".", obj)) > 1 ? split(".", obj)[1] : obj
        }
      }
    ],
    [
      # Generate transformation rules for removing columns
      for idx, blob in local.independent_blobs[full_load_name] : {
        rule-type   = "transformation"
        rule-id     = (length(local.independent_objects[full_load_name]) * 2) + idx + 1
        rule-name   = "remove-${lower(blob.column_name)}-from-${lower(blob.object_name)}"
        rule-action = "remove-column"
        rule-target = "column"
        object-locator = {
          schema-name = length(split(".", blob.object_name)) > 1 ? split(".", blob.object_name)[0] : local.independent_input_data[full_load_name].schema
          table-name  = length(split(".", blob.object_name)) > 1 ? split(".", blob.object_name)[1] : blob.object_name
          column-name = blob.column_name
        }
      }
    ],
    [
      # Generate transformation rules for removing columns
      for idx, column_to_exclude in local.independent_columns_to_exclude[full_load_name] : {
        rule-type   = "transformation"
        rule-id     = (length(local.independent_objects[full_load_name]) * 2) + idx + 1
        rule-name   = "remove-${lower(column_to_exclude.column_name)}-from-${lower(column_to_exclude.object_name)}"
        rule-action = "remove-column"
        rule-target = "column"
        object-locator = {
          schema-name = length(split(".", column_to_exclude.object_name)) > 1 ? split(".", column_to_exclude.object_name)[0] : local.independent_input_data[full_load_name].schema
          table-name  = length(split(".", column_to_exclude.object_name)) > 1 ? split(".", column_to_exclude.object_name)[1] : column_to_exclude.object_name
          column-name = column_to_exclude.column_name
        }
      }
    ],
    [
      for idx, obj in local.independent_objects[full_load_name] : {
        rule-type   = "transformation"
        rule-id     = (length(local.independent_objects[full_load_name]) * 3) + idx + 1
        rule-name   = "rename-${lower(obj)}"
        rule-action = "rename"
        rule-target = "table"
        value       = replace(obj, "_MV", "")
        object-locator = {
          schema-name = "%"
          table-name  = obj
        }
      }
      if endswith(obj, "_MV")
    ],
    ))
  }
}


output "independent_terraform_rules" {
  value = local.independent_rules
}

resource "aws_dms_replication_task" "independent_full_load_replication_task" {
  for_each                  = var.independent_full_loads
  migration_type            = "full-load"
  replication_instance_arn  = aws_dms_replication_instance.instance.replication_instance_arn
  replication_task_id       = "${var.db}-${each.value.full_load_name}"
  replication_task_settings = file("${path.module}/default_task_settings.json")
  source_endpoint_arn       = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn       = aws_dms_s3_endpoint.s3_target.endpoint_arn
  table_mappings            = jsonencode({ rules : local.independent_rules[each.key] })
  start_replication_task    = false

  tags = merge(
    { Name = each.value.full_load_name },
  var.tags)
}
