variable "environment" {
  type        = string
  description = "The environment name"
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID"
}

variable "db" {
  type        = string
  description = "The database name"
}

variable "dms_replication_instance" {
  type = object({
    replication_instance_id      = string
    subnet_group_id              = optional(string)
    subnet_group_name            = optional(string)
    subnet_ids                   = optional(list(string))
    allocated_storage            = number
    availability_zone            = string
    engine_version               = string
    kms_key_arn                  = string
    multi_az                     = bool
    replication_instance_class   = string
    inbound_cidr                 = string
    apply_immediately            = optional(bool, false)
    preferred_maintenance_window = optional(string, "sun:10:30-sun:14:30")
  })

  validation {
    condition     = contains(["3.5.2", "3.5.3", "3.5.4"], var.dms_replication_instance.engine_version)
    error_message = "Valid values for var: test_variable are ('3.5.2', '3.5.3', '3.5.4')."
  }
  description = "Properties of the dms replication instance to be used in the migration"
}

variable "dms_source" {
  type = object({
    engine_name                 = string,
    secrets_manager_arn         = string,
    secrets_manager_kms_arn     = string,
    sid                         = optional(string)
    database_name               = optional(string)
    extra_connection_attributes = optional(string)
    cdc_start_time              = optional(string)
  })

  validation {
    condition     = contains(["oracle", "postgres"], var.dms_source.engine_name)
    error_message = "Valid values for engine_name are ('oracle', 'postgres')."
  }

  validation {
    condition = (
      (
        var.dms_source.engine_name == "oracle" &&
        (var.dms_source.sid == null || var.dms_source.database_name != null)
      )
    )
    error_message = "For engine_name 'oracle' set 'sid' only, do not set 'database_name'."
  }

  validation {
    condition = (
      (
        var.dms_source.engine_name == "postgres" &&
        (var.dms_source.database_name == null || var.dms_source.sid != null)
      )
    )
    error_message = "For engine_name 'postgres' set 'database_name' only, do not set 'sid'."
  }

  description = <<EOF
    engine_name: Database engine type ('oracle' or 'postgres')
    secrets_manager_arn: ARN of the Secrets Manager secret containing database credentials
    secrets_manager_kms_arn: ARN of the KMS key encrypting the secret
    sid: Oracle SID / service name (required for Oracle)
    database_name: Database name (required for Postgres)
    extra_connection_attributes: Extra connection attributes for the DMS endpoint (e.g. "PluginName=test_decoding;" for Postgres CDC)
    cdc_start_time: The start time for the CDC task (must be after the database setup is complete to ensure logs/WAL are available)
  EOF
}

variable "validation_sqs_kms_key_arn" {
  type        = string
  description = <<EOF
    ARN of the customer-managed KMS key used to encrypt the validation SQS queues.
    If the queues receive S3 event notifications, ensure the CMK policy grants the required permissions for S3 to use the key via SQS (for example, allowing the `s3.amazonaws.com` service principal to use the key subject to appropriate conditions).
    Without these grants, Terraform may apply successfully but S3 -> SQS notifications can fail at runtime with KMS access errors.
  EOF
}

variable "output_bucket" {
  type        = string
  default     = ""
  description = <<EOF
    The name of the output bucket (optional, bucket will be generated if not specified)
    Note that if this is specified, it is assumed all related aws_s3_bucket_* resources are being managed externally and so will not be generated within this module
  EOF
}

variable "s3_target_config" {
  type = object({
    add_column_name       = bool
    max_batch_interval    = number
    min_file_size         = number
    timestamp_column_name = string
  })
  default = {
    add_column_name       = true
    max_batch_interval    = 3600
    min_file_size         = 32000
    timestamp_column_name = "EXTRACTION_TIMESTAMP"
  }
}

variable "tags" {
  type        = map(string)
  description = "tags for the module"
}

variable "create_premigration_assessment_resources" {
  type        = bool
  default     = false
  description = "Whether to create pre-requisites for DMS PreMigration Assessment to be run manually"
}

variable "retry_failed_after_recreate_metadata" {
  type        = bool
  default     = true
  description = "Whether to retry validation of failures after regenerating metadata"
}

variable "write_metadata_to_glue_catalog" {
  type        = bool
  default     = true
  description = "Whether to write metadata to glue catalog"
}

variable "valid_files_mutable" {
  type        = bool
  default     = false
  description = "If false, copy valid files to their destination bucket with a datetime infix"
}

variable "glue_catalog_arn" {
  type        = string
  default     = ""
  description = "Which glue catalog to grant metadata generator permissions to (optional)"
}

variable "glue_catalog_role_arn" {
  type        = string
  default     = ""
  description = "Which role to use to access glue catalog (optional)"
}

variable "slack_webhook_secret_id" {
  type        = string
  description = "Webhook used to send DMS alerts"
}

variable "source_rds_instance_id" {
  type        = string
  default     = null
  description = "DBInstanceIdentifier of the source RDS instance. Required when engine_name is 'postgres' to enable replication-slot CloudWatch alarms; ignored otherwise."
}

variable "postgres_replication_slot_lag_threshold_bytes" {
  type        = number
  default     = 10737418240
  description = "Threshold in bytes for the OldestReplicationSlotLag alarm on the source Postgres RDS. Default 10 GiB."
}

variable "postgres_transaction_logs_disk_usage_threshold_bytes" {
  type        = number
  default     = 53687091200
  description = "Threshold in bytes for the TransactionLogsDiskUsage alarm on the source Postgres RDS. Default 50 GiB."
}

variable "output_key_prefix" {
  type        = string
  default     = "dms_output"
  description = "The prefix to use for the output key in the S3 bucket"
}

variable "output_key_suffix" {
  type        = string
  default     = ""
  description = "The suffix to use for the output key in the S3 bucket"
}

variable "dms_mapping_rules" {
  type = object({
    bucket = string
    key    = string
  })
  description = "The path to the mapping rules file"
}

variable "replication_task_id" {
  type = object({
    full_load = string
    cdc       = optional(string)
  })
  description = "The replication task names to use for the full load and cdc tasks (cdc is optional, if not specified no cdc task will be created)"
}

variable "independent_full_loads" {
  type = map(object({
    full_load_name = string
    path = object({
      bucket = string
      key    = string
    })
  }))
  default     = {}
  description = "A list of full load tasks to be set up for tables existing in the upstream database but not downstream, including the name of the task (excluding the database name and 'full-load') and the bucket and object reference within it where the table mapping json file for the task exists"
}
