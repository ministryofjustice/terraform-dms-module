data "aws_vpc" "shared" {
  filter {
    name   = "tag:Name"
    values = ["laa-development"]
  }
}

data "aws_subnets" "data" {
  filter {
    name   = "tag:Name"
    values = ["laa-development-general-data-*"]
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.shared.id]
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
