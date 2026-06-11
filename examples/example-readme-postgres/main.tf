terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.42"
    }
  }
}

data "aws_availability_zones" "available" {}

resource "aws_secretsmanager_secret" "dms_sandbox_secret" {
  # checkov:skip=CKV2_AWS_57: Skipping because automatic rotation not needed.
  name       = "dms-sandbox-secret-postgres"
  kms_key_id = module.dms_test_kms.key_arn
}

# Example invocation of terraform-dms-module against a Postgres source.
#
# Pre-requisites the *consumer* must take care of (not provisioned here):
#   1. Source RDS Postgres parameter group sets `rds.logical_replication = 1`
#      and the instance has been rebooted to apply it.
#   2. `dms_user` exists on the source DB and has been granted the
#      `rds_replication` role plus SELECT on the tables to be migrated.
#   3. Secret in Secrets Manager contains: host, port, username, password,
#      and database (the Postgres branch of the module reads `password`,
#      not the Oracle `oracle_password,asm_password` pair).
#
# When this module is applied with engine_name = "postgres":
#   * The source endpoint receives a default ECA enabling `test_decoding`
#     and a 5s replication-slot heartbeat, unless the consumer overrides
#     `extra_connection_attributes`.
#   * If `source_rds_instance_id` is supplied, two CloudWatch alarms are
#     created on the source RDS to detect orphaned/stuck replication slots.

#trivy:ignore:AVD-AWS-0066 X-Ray tracing not currently required.
module "test_dms_implementation" {
  # checkov:skip=CKV_TF_1: ignore check in example
  # checkov:skip=CKV_TF_2: ignore check in example
  # tflint-ignore: terraform_module_pinned_source
  source = "github.com/ministryofjustice/terraform-dms-module?ref=main"

  vpc_id      = module.vpc.vpc_id
  environment = local.tags.environment-name

  db                      = aws_db_instance.dms_test.identifier
  slack_webhook_secret_id = aws_secretsmanager_secret.slack_webhook.id

  dms_replication_instance = {
    replication_instance_id    = "test-dms-postgres"
    subnet_ids                 = module.vpc.private_subnets
    subnet_group_name          = "test-dms-postgres"
    allocated_storage          = 20
    availability_zone          = data.aws_availability_zones.available.names[0]
    engine_version             = "3.5.4"
    kms_key_arn                = module.dms_test_kms.key_arn
    multi_az                   = false
    replication_instance_class = "dms.t3.medium"
    inbound_cidr               = module.vpc.vpc_cidr_block
    apply_immediately          = true
  }

  dms_source = {
    engine_name             = "postgres"
    secrets_manager_arn     = aws_secretsmanager_secret.dms_sandbox_secret.arn
    secrets_manager_kms_arn = module.dms_test_kms.key_arn
    database_name           = aws_db_instance.dms_test.db_name
    # extra_connection_attributes intentionally omitted to pick up the
    # module's default Postgres ECA (PluginName=test_decoding;HeartbeatEnable=true;...).
    # cdc_start_time is intentionally omitted so DMS starts CDC from the
    # current source stream position when the task starts.
  }

  replication_task_id = {
    full_load = "test-dms-postgres-full-load"
    cdc       = "test-dms-postgres-cdc"
  }

  # Required for the Postgres replication-slot CloudWatch alarms.
  source_rds_instance_id = aws_db_instance.dms_test.identifier

  dms_mapping_rules = {
    bucket = aws_s3_object.mappings.bucket
    key    = aws_s3_object.mappings.key
  }

  tags = local.tags

  glue_catalog_arn      = "arn:aws:glue:eu-west-1:12345678:catalog"
  glue_catalog_role_arn = "arn:aws:iam::87654321:role/de-role"
}
