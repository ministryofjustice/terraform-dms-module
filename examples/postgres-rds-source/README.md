# Postgres RDS DMS source test rig

This example provisions a throwaway PostgreSQL RDS instance in the LAA DF Dev AWS account for testing DMS source behaviour.

It creates:

- private PostgreSQL RDS instance
- custom PostgreSQL parameter group with logical replication enabled
- RDS subnet group using LAA development private/data subnets
- security group allowing PostgreSQL access from the shared VPC CIDR
- KMS key and alias for test resources
- Secrets Manager secrets for admin and DMS users (the `dms_user` role must be created manually, e.g. via the SQL runner)
- Lambda SQL runner for seeding and verification (executes arbitrary SQL; restrict invoke permissions)

This example is for development/testing only and is intended to be cleanly destroyed.

## Apply

~~~bash
terraform init
terraform plan
terraform apply
~~~

## Destroy

~~~bash
terraform destroy
~~~

## Notes

- The database is in private subnets. Use a VPN / Direct Connect / bastion host to connect.
- Secrets are stored in AWS Secrets Manager.
- The SQL runner Lambda executes arbitrary SQL; restrict invoke permissions.

## SQL runner example

Example invoke:

~~~bash
aws lambda invoke \
  --function-name "$(terraform output -raw sql_runner_lambda_name)" \
  --payload '{
    "host": "'"$(terraform output -raw postgres_endpoint)"'"",
    "port": 5432,
    "user": "postgres_admin",
    "password": "...",
    "dbname": "'"$(terraform output -raw postgres_db_name)"'"",
    "sql_statements": ["SELECT 1"]
  }' \
  /dev/stdout
~~~

The function returns an array of per-statement results.