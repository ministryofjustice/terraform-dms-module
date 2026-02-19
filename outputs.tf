output "dms_role_arn" {
  value       = aws_iam_role.dms.arn
  description = "The ARN for the AWS role created for the DMS target endpoint"
  sensitive   = true
}


output "dms_full_load_task_arn" {
  value = { for k, t in aws_dms_replication_task.full_load_replication_task : k => t.replication_task_arn }
}


output "metadata_generator_lambda_arns" {
  value = { for k, m in module.metadata_generator : k => m.lambda_function_arn }
}


output "validation_lambda_arn" {
  value       = module.validation_lambda_function.lambda_function_arn
  description = "The ARN for the validation AWS Lambda function"
}

output "dms_cdc_task_arn" {
  value       = { for k, t in aws_dms_replication_task.cdc_replication_task : k => t.replication_task_arn }
  description = "The ARN for the AWS DMS cdc task ARN"
}

output "dms_replication_instance_arn" {
  value = local.replication_instance_arn
}

output "full_load_task_arns" {
  value = { for k, t in aws_dms_replication_task.full_load_replication_task : k => t.replication_task_arn }
}

output "cdc_task_arns" {
  value = { for k, t in aws_dms_replication_task.cdc_replication_task : k => t.replication_task_arn }
}

output "metadata_generator_function_names" {
  value = { for k, m in module.metadata_generator : k => m.lambda_function_name }
}
