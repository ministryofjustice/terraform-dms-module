data "aws_secretsmanager_secret_version" "slack_webhook" {
  secret_id = var.slack_webhook_secret_id
}