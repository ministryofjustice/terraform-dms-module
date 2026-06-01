variable "name_prefix" {
  type        = string
  default     = "laa-df-dev-postgres-dms-test"
  description = <<-EOT
    Prefix applied to all named resources such as RDS, Secrets Manager secrets,
    IAM roles, KMS alias, Lambda and security groups. Set this to a per-user
    value, for example "laa-df-dev-postgres-dms-test-sb", if multiple developers
    need to run this example concurrently in the same AWS account.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase alphanumeric with hyphens only."
  }
}

variable "tags" {
  type = map(string)

  default = {
    application                      = "data-factory-laa"
    business-unit                    = "LAA"
    infrastructure-support           = "LAA-Data-Engineering@justice.gov.uk"
    owner                            = "laa-data-factory"
    environment                      = "dev"
    purpose                          = "dms-postgres-testing-throwaway"
    ticket                           = "LDF-117"
    slack-channel                    = "laa_data_engineering"
    critical-national-infrastructure = "false"
  }

  description = "Resource tags"
}
