data "aws_subnets" "subnet_ids_vpc_subnets" {
  filter {
    name = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name = "subnet-id"
    values = var.dms_replication_instance.subnet_ids
  }
}
