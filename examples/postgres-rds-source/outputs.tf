output "postgres_endpoint" {
  description = "Postgres RDS endpoint address"
  value       = aws_db_instance.postgres.address
}

output "postgres_port" {
  description = "Postgres RDS port"
  value       = aws_db_instance.postgres.port
}

output "postgres_db_name" {
  description = "Postgres database name"
  value       = aws_db_instance.postgres.db_name
}

output "postgres_instance_id" {
  description = "Postgres RDS instance identifier"
  value       = aws_db_instance.postgres.id
}

output "postgres_security_group_id" {
  description = "Security group ID attached to the Postgres RDS instance"
  value       = aws_security_group.postgres.id
}

output "postgres_admin_secret_arn" {
  description = "Secrets Manager secret ARN for the Postgres admin user"
  value       = aws_secretsmanager_secret.postgres_admin.arn
}

output "postgres_dms_user_secret_arn" {
  description = "Secrets Manager secret ARN for the Postgres DMS user"
  value       = aws_secretsmanager_secret.postgres_dms_user.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used by the Postgres test rig"
  value       = aws_kms_key.dms_test.arn
}

output "kms_alias_name" {
  description = "KMS alias name used by the Postgres test rig"
  value       = aws_kms_alias.dms_test.name
}

output "sql_runner_lambda_name" {
  description = "Name of the Postgres SQL runner Lambda"
  value       = aws_lambda_function.postgres_sql_runner.function_name
}
