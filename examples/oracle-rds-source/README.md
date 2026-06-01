# Oracle RDS DMS Test Rig

Throwaway Oracle RDS instance + helper Lambda used to exercise the
`terraform-dms-module` against a real Oracle source. Not for production use.

## What this stands up

- An Oracle RDS instance (Standard Edition Two) in the shared MP VPC private subnets
- A KMS key + alias for encryption at rest
- Two Secrets Manager secrets holding the `admin` and `dms-user` logins  <!-- pragma: allowlist secret -->
- A security group allowing access from within the VPC
- A Lambda (`oracle_sql_runner`) deployed into the same private subnets, used to
  execute arbitrary SQL against the DB without needing a bastion

It does **not** stand up DMS itself — point the DMS module at the outputs from
this stack to test replication.

## State

This example uses **local state** (no S3 backend). The state file lives next to
the config and is not shared. Don't run `terraform destroy` from a different
checkout than the one that originally applied.

## Per-developer isolation

All named resources are templated from `var.name_prefix` (default `laa-df-dev`)
so the default apply re-uses the existing shared dev stack.

If two developers want their own isolated stack in the same AWS account, set a
unique prefix:

```sh
aws-vault exec data-factory-laa-development -- \
  terraform apply -var='name_prefix=laa-df-dev-sb'
```

`name_prefix` must be lowercase alphanumeric + hyphens.

## Usage

```sh
aws-vault exec data-factory-laa-development -- terraform init
aws-vault exec data-factory-laa-development -- terraform apply
```

Useful outputs:

- `oracle_endpoint`, `oracle_port`, `oracle_db_name`
- `oracle_admin_secret_arn`, `oracle_dms_user_secret_arn`
- `sql_runner_lambda_name` — invoke with a payload like
  `{"host":"...","port":1521,"service_name":"...","username":"...","password":"...","sql_statements":["SELECT 1 FROM dual"]}`

## Tearing down

```sh
aws-vault exec data-factory-laa-development -- terraform destroy
```

Secrets have a recovery window — fully purge with
`aws secretsmanager delete-secret --force-delete-without-recovery` if you need
to re-apply the same prefix immediately.
