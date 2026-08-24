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

## Create DMS user

After provisioning the RDS instance, create the `dms_user` role via the Lambda console
(Lambda → Functions → `<name_prefix>-sql-runner` → Test):

~~~json
{
  "host": "<rds_endpoint_from_terraform_output>",
  "port": 5432,
  "user": "postgres_admin",
  "password": "<ADMIN_PASSWORD_FROM_SECRETS_MANAGER>",
  "dbname": "dmstest",
  "sql_statements": [
    "CREATE USER dms_user WITH PASSWORD '<DMS_USER_PASSWORD_FROM_SECRETS_MANAGER>' LOGIN",
    "GRANT rds_replication TO dms_user",
    "GRANT USAGE ON SCHEMA public TO dms_user",
    "GRANT CREATE ON SCHEMA public TO dms_user",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO dms_user"
  ]
}
~~~

## Seed test data (50k rows)

Create tables and insert test data covering key Postgres types (JSONB, TIMESTAMPTZ, UUID, TEXT[], INTERVAL, NUMERIC, etc.):

~~~json
{
  "host": "<rds_endpoint_from_terraform_output>",
  "port": 5432,
  "user": "postgres_admin",
  "password": "<ADMIN_PASSWORD_FROM_SECRETS_MANAGER>",
  "dbname": "dmstest",
  "sql_statements": [
    "CREATE TABLE customers (id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(255), created_at TIMESTAMPTZ DEFAULT NOW(), metadata JSONB, is_active BOOLEAN DEFAULT true)",
    "CREATE TABLE orders (id SERIAL PRIMARY KEY, customer_id INTEGER REFERENCES customers(id), order_date DATE NOT NULL, total_amount NUMERIC(12,2), status VARCHAR(20), notes TEXT, tracking_id UUID DEFAULT gen_random_uuid())",
    "CREATE TABLE products (id SERIAL PRIMARY KEY, sku VARCHAR(50) UNIQUE NOT NULL, name VARCHAR(200), price NUMERIC(10,2), weight_kg DOUBLE PRECISION, tags TEXT[], image_data BYTEA, updated_at TIMESTAMP)",
    "CREATE TABLE audit_log (id BIGSERIAL PRIMARY KEY, table_name VARCHAR(100), operation VARCHAR(10), old_values JSONB, new_values JSONB, changed_at TIMESTAMPTZ DEFAULT NOW(), session_duration INTERVAL)",
    "INSERT INTO customers (name, email, metadata, is_active) SELECT 'Customer ' || g, 'customer' || g || '@example.com', jsonb_build_object('tier', CASE WHEN g % 3 = 0 THEN 'gold' WHEN g % 3 = 1 THEN 'silver' ELSE 'bronze' END, 'score', g % 100), g % 5 != 0 FROM generate_series(1, 10000) g",
    "INSERT INTO orders (customer_id, order_date, total_amount, status, notes) SELECT (g % 10000) + 1, CURRENT_DATE - (g % 365), round((random() * 1000)::numeric, 2), CASE g % 4 WHEN 0 THEN 'pending' WHEN 1 THEN 'shipped' WHEN 2 THEN 'delivered' ELSE 'cancelled' END, CASE WHEN g % 10 = 0 THEN 'Rush delivery requested' ELSE NULL END FROM generate_series(1, 20000) g",
    "INSERT INTO products (sku, name, price, weight_kg, tags, updated_at) SELECT 'SKU-' || lpad(g::text, 6, '0'), 'Product ' || g, round((random() * 500 + 1)::numeric, 2), round((random() * 50)::numeric, 3), ARRAY['tag' || (g % 5), 'cat' || (g % 10)], NOW() - (g || ' hours')::interval FROM generate_series(1, 5000) g",
    "INSERT INTO audit_log (table_name, operation, old_values, new_values, session_duration) SELECT CASE g % 3 WHEN 0 THEN 'customers' WHEN 1 THEN 'orders' ELSE 'products' END, CASE g % 3 WHEN 0 THEN 'UPDATE' WHEN 1 THEN 'INSERT' ELSE 'DELETE' END, CASE WHEN g % 3 != 1 THEN jsonb_build_object('id', g, 'old_field', 'old_val') ELSE NULL END, CASE WHEN g % 3 != 2 THEN jsonb_build_object('id', g, 'new_field', 'new_val') ELSE NULL END, (g || ' minutes')::interval FROM generate_series(1, 15000) g",
    "GRANT SELECT ON ALL TABLES IN SCHEMA public TO dms_user"
  ]
}
~~~

| Table | Rows | Key Types Tested |
|-------|------|-----------------|
| `customers` | 10,000 | SERIAL, VARCHAR, TIMESTAMPTZ, JSONB, BOOLEAN |
| `orders` | 20,000 | INTEGER FK, DATE, NUMERIC(12,2), UUID, TEXT |
| `products` | 5,000 | VARCHAR UNIQUE, DOUBLE PRECISION, TEXT[], BYTEA, TIMESTAMP |
| `audit_log` | 15,000 | BIGSERIAL, JSONB (nullable), INTERVAL |
