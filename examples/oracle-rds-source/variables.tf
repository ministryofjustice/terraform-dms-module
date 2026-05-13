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
