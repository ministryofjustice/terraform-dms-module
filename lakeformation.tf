locals {
  lf_enabled = var.lakeformation_grants != null
  lf_database_name = local.lf_enabled ? coalesce(
    var.lakeformation_grants.database_name,
    local.database_credentials["dbInstanceIdentifier"],
  ) : null

  lf_table_grants = local.lf_enabled ? {
    for principal in var.lakeformation_grants.principals : principal => principal
  } : {}

  lf_database_grants = (local.lf_enabled && var.lakeformation_grants.grant_database_describe) ? {
    for principal in var.lakeformation_grants.principals : principal => principal
  } : {}
}

resource "aws_lakeformation_permissions" "select_all_tables" {
  for_each = local.lf_table_grants

  principal   = each.value
  permissions = var.lakeformation_grants.permissions

  table_with_columns {
    database_name = local.lf_database_name
    name          = "ALL_TABLES"
    wildcard      = true
  }
}

resource "aws_lakeformation_permissions" "describe_database" {
  for_each = local.lf_database_grants

  principal   = each.value
  permissions = ["DESCRIBE"]

  database {
    name = local.lf_database_name
  }
}
