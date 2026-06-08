variable "name_prefix" {
  type        = string
  default     = "postgres-dms-example"
  description = <<-EOT
    Prefix applied to all named resources such as RDS, Secrets Manager secrets,
    IAM roles, KMS alias, Lambda and security groups. Set this to a per-user
    value, for example "postgres-dms-example-sb", if multiple developers need
    to run this example concurrently in the same AWS account.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens only."
  }
}

variable "tags" {
  type = map(string)

  default = {
    application                      = "my-application"
    business-unit                    = "my-business-unit"
    infrastructure-support           = "team@example.com"
    owner                            = "my-team"
    environment                      = "dev"
    purpose                          = "dms-postgres-testing-throwaway"
    ticket                           = "TICKET-123"
    slack-channel                    = "my-team"
    critical-national-infrastructure = "false"
  }

  description = "Resource tags"
}
