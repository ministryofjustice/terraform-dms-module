output "dms_role_arn" {
  value       = aws_iam_role.dms.arn
  description = "The ARN for the AWS role created for the DMS target endpoint"
  sensitive   = true
}


output "dms_full_load_task_arn" {
  value       = aws_dms_replication_task.full_load_replication_task.replication_task_arn
  description = "The ARN for the AWS DMS full-load task ARN"
}

output "metadata_generator_lambda_arn" {
  value       = module.metadata_generator.lambda_function_arn
  description = "The ARN for the metadata_generator AWS Lambda function"
}

output "validation_lambda_arn" {
  value       = module.validation_lambda_function.lambda_function_arn
  description = "The ARN for the validation AWS Lambda function"
}

output "dms_cdc_task_arn" {
  value       = aws_dms_replication_task.cdc_replication_task.replication_task_arn
  description = "The ARN for the AWS DMS cdc task ARN"
}
