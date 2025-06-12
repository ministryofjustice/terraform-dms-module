data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_subnets" "subnet_ids_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "subnet-id"
    values = var.dms_replication_instance.subnet_ids
  }
}

data "aws_secretsmanager_secret_version" "database_credentials" {
  secret_id = var.dms_source.secrets_manager_arn
}

locals {
  database_credentials = jsondecode(data.aws_secretsmanager_secret_version.database_credentials.secret_string)
}
