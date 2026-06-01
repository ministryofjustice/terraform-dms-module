# Postgres RDS DMS source test rig

This example provisions a throwaway PostgreSQL RDS instance in the LAA DF Dev AWS account for testing DMS source behaviour.

It creates:

- private PostgreSQL RDS instance
- custom PostgreSQL parameter group with logical replication enabled
- RDS subnet group using LAA development private/data subnets
- security group allowing PostgreSQL access from the shared VPC CIDR
- KMS key and alias for test resources
- Secrets Manager secrets for admin and DMS users
- optional Lambda SQL runner for seeding and verification

This example is for development/testing only and is intended to be cleanly destroyed.

## Apply

```bash
terraform init
terraform plan
terraform apply