output "oracle_endpoint" {
  value = aws_db_instance.oracle.address
}

output "oracle_port" {
  value = aws_db_instance.oracle.port
}

output "oracle_db_name" {
  value = aws_db_instance.oracle.db_name
}

output "oracle_admin_secret_arn" {
  value = aws_secretsmanager_secret.oracle_admin.arn
}

output "oracle_dms_user_secret_arn" {
  value = aws_secretsmanager_secret.oracle_dms_user.arn
}

output "oracle_security_group_id" {
  value = aws_security_group.oracle.id
}

output "oracle_instance_id" {
  value = aws_db_instance.oracle.id
}

output "sql_runner_lambda_name" {
  value = aws_lambda_function.oracle_sql_runner.function_name
}
