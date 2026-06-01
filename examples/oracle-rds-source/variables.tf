variable "name_prefix" {
  type        = string
  default     = "laa-df-dev"
  description = <<-EOT
    Prefix applied to all named resources (DB, secrets, IAM roles, KMS alias,
    Lambda, security groups). Set this to a per-user value (e.g. "laa-df-dev-sb")
    if multiple developers need to run this example concurrently in the same
    AWS account, otherwise resource name collisions will cause apply to fail.
  EOT

  validation {
    # Most resource names allow alphanumerics + hyphens; secret/KMS aliases also
    # allow forward slashes but we keep things conservative here.
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
    purpose                          = "dms-testing-throwaway"
    ticket                           = "LDF-55"
    slack-channel                    = "laa_data_engineering"
    critical-national-infrastructure = "false"
  }
  description = "Resource tags"
}
