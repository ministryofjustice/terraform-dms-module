<!-- BEGIN_TF_DOCS -->
# DMS Terraform Module
This Terraform module provisions an AWS DMS (Database Migration Service) setup for replicating data from an Oracle database to an S3-based data lake architecture. It automates the creation and configuration of the following components:
- A DMS replication instance and endpoints
- Oracle source configuration (via Secrets Manager)
- S3 target configuration
- CDC (Change Data Capture) and full-load replication tasks
- Optional pre-migration assessment resources
- Optional metadata publishing to AWS Glue Catalog
- IAM roles and policies required for DMS operations
- Lambda functions for metadata generation and validation
- Alerts via Slack webhook


# Architecture Overview
![DMS Module Diagram](https://github.com/ministryofjustice/terraform-dms-module/blob/main/terraform-dms-module.png)

*Figure: End-to-end DMS pipeline for Oracle to S3 replication with validation, landing, failure handling and Glue integration*

## Example

```hcl
terraform {
  required_version = ">= 1.0.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_availability_zones" "available" {}
resource "aws_secretsmanager_secret" "dms_sandbox_secret" {
  # checkov:skip=CKV2_AWS_57: Skipping because automatic rotation not needed.
  name       = "dms-sandbox-secret"
  kms_key_id = module.dms_test_kms.key_arn
}

module "test_dms_implementation" {
  # checkov:skip=CKV_TF_1: ignore check in example
  # checkov:skip=CKV_TF_2: ignore check in example
  source = "github.com/ministryofjustice/terraform-dms-module"

  vpc_id      = module.vpc.vpc_id
  environment = local.tags.environment-name

  db                      = aws_db_instance.dms_test.identifier
  slack_webhook_secret_id = aws_secretsmanager_secret.slack_webhook.id
  dms_replication_instance = {
    replication_instance_id    = "test-dms"
    subnet_ids                 = module.vpc.private_subnets
    subnet_group_name          = "test-dms"
    allocated_storage          = 20
    availability_zone          = data.aws_availability_zones.available.names[0]
    engine_version             = "3.5.4"
    kms_key_arn                = module.dms_test_kms.key_arn
    multi_az                   = false
    replication_instance_class = "dms.t3.large"
    inbound_cidr               = module.vpc.vpc_cidr_block
    apply_immediately          = true
  }

  dms_source = {
    engine_name                 = "oracle"
    secrets_manager_arn         = aws_secretsmanager_secret.dms_sandbox_secret.arn
    secrets_manager_kms_arn     = module.dms_test_kms.key_arn
    sid                         = aws_db_instance.dms_test.db_name
    extra_connection_attributes = "addSupplementalLogging=N;useBfile=Y;useLogminerReader=N;"
    cdc_start_time              = "2025-04-02T12:00:00Z"
  }

  replication_task_id = {
    full_load = "test-dms-full-load"
    cdc       = "test-dms-cdc"
  }

  dms_mapping_rules = {
    bucket = aws_s3_object.mappings.bucket
    key    = aws_s3_object.mappings.key
  }
  #output_bucket         = module.test_dms_rawhist

  tags = local.tags


  glue_catalog_arn = "arn:aws:glue:eu-west-1:684969100054:catalog"
}
```

## Note

Update the mappings.json to specify the mappings for the DMS task.
This will be used to select the tables to be migrated.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_create_premigration_assessement_resources"></a> [create\_premigration\_assessement\_resources](#input\_create\_premigration\_assessement\_resources) | whether to create pre-requisites for DMS PreMigration Assessment to be run manually | `bool` | `false` | no |
| <a name="input_db"></a> [db](#input\_db) | The database name | `string` | n/a | yes |
| <a name="input_dms_mapping_rules"></a> [dms\_mapping\_rules](#input\_dms\_mapping\_rules) | The path to the mapping rules file | <pre>object({<br/>    bucket = string<br/>    key    = string<br/>  })</pre> | n/a | yes |
| <a name="input_dms_replication_instance"></a> [dms\_replication\_instance](#input\_dms\_replication\_instance) | n/a | <pre>object({<br/>    replication_instance_id      = string<br/>    subnet_group_id              = optional(string)<br/>    subnet_group_name            = optional(string)<br/>    subnet_ids                   = optional(list(string))<br/>    allocated_storage            = number<br/>    availability_zone            = string<br/>    engine_version               = string<br/>    kms_key_arn                  = string<br/>    multi_az                     = bool<br/>    replication_instance_class   = string<br/>    inbound_cidr                 = string<br/>    apply_immediately            = optional(bool, false)<br/>    preferred_maintenance_window = optional(string, "sun:10:30-sun:14:30")<br/>  })</pre> | n/a | yes |
| <a name="input_dms_source"></a> [dms\_source](#input\_dms\_source) | extra\_connection\_attributes: Extra connection attributes to be used in the connection string</br><br/>    cdc\_start\_time: The start time for the CDC task, this will need to be set to a date after the Oracle database setup has been complete (this is to ensure the logs are available) | <pre>object({<br/>    engine_name                 = string,<br/>    secrets_manager_arn         = string,<br/>    secrets_manager_kms_arn     = string,<br/>    sid                         = string,<br/>    extra_connection_attributes = optional(string)<br/>    cdc_start_time              = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment name | `string` | n/a | yes |
| <a name="input_glue_catalog_arn"></a> [glue\_catalog\_arn](#input\_glue\_catalog\_arn) | Which glue catalog to grant metadata generator permissions to (optional) | `string` | `""` | no |
| <a name="input_glue_catalog_role_arn"></a> [glue\_catalog\_role\_arn](#input\_glue\_catalog\_role\_arn) | Which role to use to access glue catalog (optional) | `string` | `""` | no |
| <a name="input_output_bucket"></a> [output\_bucket](#input\_output\_bucket) | The name of the output bucket (optional, bucket will be generated if not specified)<br/>    Note that if this is specified, it is assumed all related aws\_s3\_bucket\_* resources are being managed externally and so will not be generated within this module | `string` | `""` | no |
| <a name="input_output_key_prefix"></a> [output\_key\_prefix](#input\_output\_key\_prefix) | The prefix to use for the output key in the S3 bucket | `string` | `"dms_output"` | no |
| <a name="input_output_key_suffix"></a> [output\_key\_suffix](#input\_output\_key\_suffix) | The suffix to use for the output key in the S3 bucket | `string` | `""` | no |
| <a name="input_replication_task_id"></a> [replication\_task\_id](#input\_replication\_task\_id) | n/a | <pre>object({<br/>    full_load = string<br/>    cdc       = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_retry_failed_after_recreate_metadata"></a> [retry\_failed\_after\_recreate\_metadata](#input\_retry\_failed\_after\_recreate\_metadata) | Whether to retry validation of failures after regenerating metadata | `bool` | `true` | no |
| <a name="input_s3_target_config"></a> [s3\_target\_config](#input\_s3\_target\_config) | n/a | <pre>object({<br/>    add_column_name       = bool<br/>    max_batch_interval    = number<br/>    min_file_size         = number<br/>    timestamp_column_name = string<br/>  })</pre> | <pre>{<br/>  "add_column_name": true,<br/>  "max_batch_interval": 3600,<br/>  "min_file_size": 32000,<br/>  "timestamp_column_name": "EXTRACTION_TIMESTAMP"<br/>}</pre> | no |
| <a name="input_slack_webhook_secret_id"></a> [slack\_webhook\_secret\_id](#input\_slack\_webhook\_secret\_id) | webhook used to send dms alerts | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | n/a | yes |
| <a name="input_valid_files_mutable"></a> [valid\_files\_mutable](#input\_valid\_files\_mutable) | If false, copy valid files to their destination bucket with a datetime infix | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC ID | `string` | n/a | yes |
| <a name="input_write_metadata_to_glue_catalog"></a> [write\_metadata\_to\_glue\_catalog](#input\_write\_metadata\_to\_glue\_catalog) | Whether to write metdata to glue catalog | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dms_full_load_task_arn"></a> [dms\_full\_load\_task\_arn](#output\_dms\_full\_load\_task\_arn) | The ARN for the AWS DMS full-load task ARN |
| <a name="output_dms_role_arn"></a> [dms\_role\_arn](#output\_dms\_role\_arn) | The ARN for the AWS role created for the DMS target endpoint |
| <a name="output_metadata_generator_lambda_arn"></a> [metadata\_generator\_lambda\_arn](#output\_metadata\_generator\_lambda\_arn) | The ARN for the metadata\_generator AWS Lambda function |
| <a name="output_terraform_rules"></a> [terraform\_rules](#output\_terraform\_rules) | n/a |
| <a name="output_validation_lambda_arn"></a> [validation\_lambda\_arn](#output\_validation\_lambda\_arn) | The ARN for the validation AWS Lambda function |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.dms_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_dms_endpoint.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_replication_instance.instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_instance) | resource |
| [aws_dms_replication_subnet_group.replication_subnet_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_subnet_group) | resource |
| [aws_dms_replication_task.cdc_replication_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_dms_replication_task.full_load_replication_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_dms_s3_endpoint.s3_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_s3_endpoint) | resource |
| [aws_iam_role.dms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_premigration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.eventbridge](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.dms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.dms_premigration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.eventbridge_sns_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.dms-cloudwatch-logs-role-AmazonDMSCloudWatchLogsRole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.dms-vpc-role-AmazonDMSVPCManagementRole](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_permission.allow_landing_bucket_to_invoke_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [aws_s3_bucket.invalid](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.premigration_assessment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.raw_history](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.validation_metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_notification.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_notification) | resource |
| [aws_s3_bucket_ownership_controls.invalid](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.premigration_assessment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.raw_history](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_ownership_controls.validation_metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_ownership_controls) | resource |
| [aws_s3_bucket_public_access_block.invalid](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.premigration_assessment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.raw_history](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.validation_metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.invalid](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.premigration_assessment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.raw_history](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.validation_metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.invalid](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.landing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.premigration_assessment](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.raw_history](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.validation_metadata](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_security_group.metadata_generator_lambda_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.replication_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_sns_topic.dms_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_vpc_security_group_egress_rule.replication_instance_outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
<!-- END_TF_DOCS -->
