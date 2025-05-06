<!-- BEGIN_TF_DOCS -->
# RDS Export Terraform Module

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

locals {
  name = "test-dms"
  tags = {
    business-unit    = "HMPPS"
    application      = "Data Engineering"
    environment-name = "sandbox"
    is-production    = "False"
    owner            = "DMET"
    team-name        = "DMET"
    namespace        = "dmet-test"
  }
}

module "dms" {
  source = "github.com/ministryofjustice/analytical-platform//terraform/aws/modules/data-engineering/dms?ref=66a7d870"

  environment = local.tags.environment-name
  vpc_id      = module.vpc.vpc_id
  db          = aws_db_instance.dms_test.identifier

  dms_replication_instance = {
    replication_instance_id    = aws_db_instance.dms_test.identifier
    subnet_ids                 = module.vpc.private_subnets
    subnet_group_name          = local.name
    allocated_storage          = 20
    availability_zone          = data.aws_availability_zones.available.names[0]
    engine_version             = "3.5.4"
    multi_az                   = false
    replication_instance_class = "dms.t2.micro"
    inbound_cidr               = module.vpc.vpc_cidr_block
  }

  dms_source = {
    engine_name                 = "oracle"
    secrets_manager_arn         = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:dms-user-secret"
    sid                         = aws_db_instance.dms_test.db_name
    extra_connection_attributes = "addSupplementalLogging=N;useBfile=Y;useLogminerReader=N;"
    cdc_start_time              = "2025-01-29T11:00:00Z"
  }

  replication_task_id = {
    full_load = "${aws_db_instance.dms_test.identifier}-full-load"
    cdc       = "${aws_db_instance.dms_test.identifier}-cdc"
  }

  dms_mapping_rules     = "${path.module}/mappings.json"
  landing_bucket        = aws_s3_bucket.landing.bucket
  landing_bucket_folder = "${local.tags.team-name}/${aws_db_instance.dms_test.identifier}"

  tags = local.tags
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
| <a name="input_dms_mapping_rules"></a> [dms\_mapping\_rules](#input\_dms\_mapping\_rules) | The path to the mapping rules file | `string` | n/a | yes |
| <a name="input_dms_replication_instance"></a> [dms\_replication\_instance](#input\_dms\_replication\_instance) | n/a | <pre>object({<br/>    replication_instance_id      = string<br/>    subnet_group_id              = optional(string)<br/>    subnet_group_name            = optional(string)<br/>    subnet_ids                   = optional(list(string))<br/>    allocated_storage            = number<br/>    availability_zone            = string<br/>    engine_version               = string<br/>    kms_key_arn                  = optional(string)<br/>    multi_az                     = bool<br/>    replication_instance_class   = string<br/>    inbound_cidr                 = string<br/>    apply_immediately            = optional(bool, false)<br/>    preferred_maintenance_window = optional(string, "sun:10:30-sun:14:30")<br/>  })</pre> | n/a | yes |
| <a name="input_dms_source"></a> [dms\_source](#input\_dms\_source) | extra\_connection\_attributes: Extra connection attributes to be used in the connection string</br><br/>    cdc\_start\_time: The start time for the CDC task, this will need to be set to a date after the Oracle database setup has been complete (this is to ensure the logs are available) | <pre>object({<br/>    engine_name                 = string,<br/>    secrets_manager_arn         = string,<br/>    secrets_manager_kms_arn     = string,<br/>    sid                         = string,<br/>    extra_connection_attributes = optional(string)<br/>    cdc_start_time              = optional(string)<br/>    asm_secret_id               = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment name | `string` | n/a | yes |
| <a name="input_glue_catalog_arn"></a> [glue\_catalog\_arn](#input\_glue\_catalog\_arn) | Which glue catalog to grant metadata generator permissions to (optional) | `string` | `""` | no |
| <a name="input_glue_catalog_role_arn"></a> [glue\_catalog\_role\_arn](#input\_glue\_catalog\_role\_arn) | Which role to use to access glue catalog (optional) | `string` | `""` | no |
| <a name="input_output_bucket"></a> [output\_bucket](#input\_output\_bucket) | The name of the output bucket (optional, bucket will be generated if not specified)<br/>    Note that if this is specified, it is assumed all related aws\_s3\_bucket\_* resources are being managed externally and so will not be generated within this module | `string` | `""` | no |
| <a name="input_replication_task_id"></a> [replication\_task\_id](#input\_replication\_task\_id) | n/a | <pre>object({<br/>    full_load = string<br/>    cdc       = optional(string)<br/>  })</pre> | n/a | yes |
| <a name="input_retry_failed_after_recreate_metadata"></a> [retry\_failed\_after\_recreate\_metadata](#input\_retry\_failed\_after\_recreate\_metadata) | Whether to retry validation of failures after regenerating metadata | `bool` | `true` | no |
| <a name="input_s3_target_config"></a> [s3\_target\_config](#input\_s3\_target\_config) | n/a | <pre>object({<br/>    add_column_name       = bool<br/>    max_batch_interval    = number<br/>    min_file_size         = number<br/>    timestamp_column_name = string<br/>  })</pre> | <pre>{<br/>  "add_column_name": true,<br/>  "max_batch_interval": 3600,<br/>  "min_file_size": 32000,<br/>  "timestamp_column_name": "EXTRACTION_TIMESTAMP"<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | n/a | `map(string)` | n/a | yes |
| <a name="input_valid_files_mutable"></a> [valid\_files\_mutable](#input\_valid\_files\_mutable) | If false, copy valid files to their destination bucket with a datetime infix | `bool` | `false` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The VPC ID | `string` | n/a | yes |
| <a name="input_write_metadata_to_glue_catalog"></a> [write\_metadata\_to\_glue\_catalog](#input\_write\_metadata\_to\_glue\_catalog) | Whether to write metdata to glue catalog | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dms_full_load_task_arn"></a> [dms\_full\_load\_task\_arn](#output\_dms\_full\_load\_task\_arn) | The ARN for the AWS DMS full-load task ARN |
| <a name="output_dms_role_arn"></a> [dms\_role\_arn](#output\_dms\_role\_arn) | The ARN for the AWS role created for the DMS target endpoint |
| <a name="output_dms_source_role_arn"></a> [dms\_source\_role\_arn](#output\_dms\_source\_role\_arn) | The ARN for the AWS role created for the DMS source endpoint |
| <a name="output_metadata_generator_lambda_arn"></a> [metadata\_generator\_lambda\_arn](#output\_metadata\_generator\_lambda\_arn) | The ARN for the metadata\_generator AWS Lambda function |
| <a name="output_terraform_rules"></a> [terraform\_rules](#output\_terraform\_rules) | n/a |
| <a name="output_validation_lambda_arn"></a> [validation\_lambda\_arn](#output\_validation\_lambda\_arn) | The ARN for the validation AWS Lambda function |

## Resources

| Name | Type |
|------|------|
| [aws_dms_endpoint.source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_endpoint) | resource |
| [aws_dms_replication_instance.instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_instance) | resource |
| [aws_dms_replication_subnet_group.replication_subnet_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_subnet_group) | resource |
| [aws_dms_replication_task.cdc_replication_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_dms_replication_task.full_load_replication_task](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_replication_task) | resource |
| [aws_dms_s3_endpoint.s3_target](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dms_s3_endpoint) | resource |
| [aws_iam_role.dms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_premigration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dms_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.dms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.dms_premigration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.dms_source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
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
| [aws_s3_object.dms_mapping_rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_object) | resource |
| [aws_security_group.metadata_generator_lambda_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.replication_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.replication_instance_outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
<!-- END_TF_DOCS -->
