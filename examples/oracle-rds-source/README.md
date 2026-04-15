# Oracle RDS Source — Throwaway Test Rig

Provisions a throwaway Oracle RDS instance in the LAA DF Dev account for DMS module testing.

## What it creates

| Resource | Name / ID |
|---|---|
| Oracle RDS SE2 19c (`db.m5.large`, 20 GB gp3) | `laa-df-dev-oracle-dms-test` |
| DB parameter group (`enable_goldengate_replication=TRUE`) | `laa-df-dev-oracle-dms` |
| DB subnet group (shared MP data subnets) | `laa-df-dev-oracle-dms-test` |
| KMS key + alias | `alias/laa-df-dev-dms-test` |
| Security group (ingress 1521 from VPC CIDR) | `laa-df-dev-oracle-dms-test` |
| Secrets Manager secrets (admin + dms-user) | `laa-df-dev/oracle-dms-test/admin`, `…/dms-user` |
| Lambda SQL runner (Python 3.12 + oracledb) | `laa-df-dev-oracle-sql-runner` |
| Lambda security group (egress 1521) | `laa-df-dev-oracle-sql-runner` |
| Lambda layer (oracledb thin mode) | `oracledb-thin` |
| IAM role for Lambda | `laa-df-dev-oracle-sql-runner` |

## Prerequisites

- **AWS access**: `aws-vault` configured with profile `data-factory-laa-development`
  - SSO start URL: `https://moj.awsapps.com/start`
  - SSO region: `eu-west-2`
  - SSO role: `modernisation-platform-sandbox`
  - Account: `307869868585`
- **Terraform** >= 1.10
- **Python 3** with `pip3` available on PATH
- Region: `eu-west-2` (London)

## Deploy

```bash
cd examples/oracle-rds-source

# Initialise Terraform
aws-vault exec data-factory-laa-development -- terraform init

# Plan and apply
aws-vault exec data-factory-laa-development -- terraform plan
aws-vault exec data-factory-laa-development -- terraform apply
```

The Lambda layer build (`null_resource.build_oracledb_layer`) runs `pip3 install oracledb` targeting `manylinux2014_x86_64` / Python 3.12 automatically during apply.

## Post-deploy setup

After `terraform apply` completes, run these steps via the Lambda SQL runner to prepare the database for DMS.

### 1. Get credentials

```bash
# Admin password
AWS_REGION=eu-west-2 AWS_PAGER="" aws-vault exec data-factory-laa-development -- \
  aws secretsmanager get-secret-value \
  --secret-id "laa-df-dev/oracle-dms-test/admin" \
  --query "SecretString" --output text

# DMS user password
AWS_REGION=eu-west-2 AWS_PAGER="" aws-vault exec data-factory-laa-development -- \
  aws secretsmanager get-secret-value \
  --secret-id "laa-df-dev/oracle-dms-test/dms-user" \
  --query "SecretString" --output text
```

### 2. Test connectivity

```bash
AWS_REGION=eu-west-2 AWS_PAGER="" aws-vault exec data-factory-laa-development -- \
  aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{"host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST","sql_statements":["SELECT 1 FROM DUAL"]}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda_output.json && cat /tmp/lambda_output.json
```

Replace `<ENDPOINT>` and `<ADMIN_PASSWORD>` from step 1. You can also use the **Lambda console** Test tab with the same JSON payload.

### 3. Enable supplemental logging

Required for DMS CDC (Change Data Capture). Uses `rdsadmin` since this is RDS (not self-managed Oracle).

```bash
aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{
    "host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST",
    "sql_statements":[
      "BEGIN rdsadmin.rdsadmin_util.alter_supplemental_logging(p_action => '\''ADD'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.alter_supplemental_logging(p_action => '\''ADD'\'', p_type => '\''PRIMARY KEY'\''); END;"
    ]
  }' \
  --cli-binary-format raw-in-base64-out /tmp/suplog.json && cat /tmp/suplog.json
```

Verify:

```sql
SELECT SUPPLEMENTAL_LOG_DATA_MIN, SUPPLEMENTAL_LOG_DATA_PK FROM V$DATABASE
-- Expected: YES, YES
```

### 4. Create DMS user

```bash
aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{
    "host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST",
    "sql_statements":[
      "CREATE USER dms_user IDENTIFIED BY \"<DMS_USER_PASSWORD>\"",
      "GRANT CREATE SESSION TO dms_user",
      "GRANT SELECT ANY TABLE TO dms_user",
      "GRANT SELECT ANY TRANSACTION TO dms_user",
      "GRANT LOGMINING TO dms_user"
    ]
  }' \
  --cli-binary-format raw-in-base64-out /tmp/dmsuser.json && cat /tmp/dmsuser.json
```

Then grant V$ and SYS object access via `rdsadmin` (required on RDS):

```bash
aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{
    "host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST",
    "sql_statements":[
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$ARCHIVED_LOG'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$LOG'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$LOGFILE'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$LOGMNR_LOGS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$LOGMNR_CONTENTS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$DATABASE'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$THREAD'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$PARAMETER'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$NLS_PARAMETERS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$TIMEZONE_NAMES'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''V_$TRANSACTION'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''DBMS_LOGMNR'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''EXECUTE'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_INDEXES'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_OBJECTS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_TABLES'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_USERS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_CATALOG'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_CONSTRAINTS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_CONS_COLUMNS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_TAB_COLS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_IND_COLUMNS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''ALL_LOG_GROUPS'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;",
      "BEGIN rdsadmin.rdsadmin_util.grant_sys_object(p_obj_name=>'\''DBA_TABLESPACES'\'',p_grantee=>'\''DMS_USER'\'',p_privilege=>'\''SELECT'\''); END;"
    ]
  }' \
  --cli-binary-format raw-in-base64-out /tmp/grants.json && cat /tmp/grants.json
```

### 5. Seed test data

```bash
aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{
    "host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST",
    "sql_statements":[
      "CREATE TABLE ADMIN.EMPLOYEES (EMP_ID NUMBER(10) PRIMARY KEY, FIRST_NAME VARCHAR2(50), LAST_NAME VARCHAR2(50), EMAIL VARCHAR2(100), HIRE_DATE DATE, SALARY NUMBER(10,2), DEPARTMENT_ID NUMBER(5), IS_ACTIVE NUMBER(1) DEFAULT 1, CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP)",
      "CREATE TABLE ADMIN.DEPARTMENTS (DEPT_ID NUMBER(5) PRIMARY KEY, DEPT_NAME VARCHAR2(100) NOT NULL, LOCATION VARCHAR2(100), MANAGER_ID NUMBER(10), BUDGET NUMBER(15,2), CREATED_AT TIMESTAMP DEFAULT SYSTIMESTAMP)",
      "CREATE TABLE ADMIN.AUDIT_LOG (LOG_ID NUMBER(10) PRIMARY KEY, TABLE_NAME VARCHAR2(50), OPERATION VARCHAR2(10), RECORD_ID NUMBER(10), OLD_VALUE CLOB, NEW_VALUE CLOB, CHANGED_BY VARCHAR2(50), CHANGED_AT TIMESTAMP DEFAULT SYSTIMESTAMP)"
    ]
  }' \
  --cli-binary-format raw-in-base64-out /tmp/tables.json && cat /tmp/tables.json
```

Then populate (50k employees, 20 departments, 10k audit logs):

```bash
aws lambda invoke \
  --function-name laa-df-dev-oracle-sql-runner \
  --payload '{
    "host":"<ENDPOINT>","port":1521,"user":"admin","password":"<ADMIN_PASSWORD>","service_name":"DMSTEST",
    "sql_statements":[
      "INSERT INTO ADMIN.DEPARTMENTS (DEPT_ID, DEPT_NAME, LOCATION, BUDGET) SELECT LEVEL, '\''Department '\'' || LEVEL, CASE MOD(LEVEL,4) WHEN 0 THEN '\''London'\'' WHEN 1 THEN '\''Manchester'\'' WHEN 2 THEN '\''Birmingham'\'' ELSE '\''Leeds'\'' END, ROUND(DBMS_RANDOM.VALUE(100000,5000000),2) FROM DUAL CONNECT BY LEVEL <= 20",
      "BEGIN FOR i IN 1..50000 LOOP INSERT INTO ADMIN.EMPLOYEES (EMP_ID, FIRST_NAME, LAST_NAME, EMAIL, HIRE_DATE, SALARY, DEPARTMENT_ID, IS_ACTIVE) VALUES (i, '\''First'\'' || i, '\''Last'\'' || i, '\''emp'\'' || i || '\''@example.com'\'', SYSDATE - DBMS_RANDOM.VALUE(1,3650), ROUND(DBMS_RANDOM.VALUE(25000,120000),2), MOD(i,20)+1, CASE WHEN DBMS_RANDOM.VALUE(0,1) > 0.1 THEN 1 ELSE 0 END); IF MOD(i,5000)=0 THEN COMMIT; END IF; END LOOP; COMMIT; END;",
      "BEGIN FOR i IN 1..10000 LOOP INSERT INTO ADMIN.AUDIT_LOG (LOG_ID, TABLE_NAME, OPERATION, RECORD_ID, OLD_VALUE, NEW_VALUE, CHANGED_BY) VALUES (i, CASE MOD(i,2) WHEN 0 THEN '\''EMPLOYEES'\'' ELSE '\''DEPARTMENTS'\'' END, CASE MOD(i,3) WHEN 0 THEN '\''INSERT'\'' WHEN 1 THEN '\''UPDATE'\'' ELSE '\''DELETE'\'' END, MOD(i,50000)+1, '\''old_val_'\'' || i, '\''new_val_'\'' || i, '\''user'\'' || MOD(i,10)); IF MOD(i,5000)=0 THEN COMMIT; END IF; END LOOP; COMMIT; END;"
    ]
  }' \
  --cli-binary-format raw-in-base64-out /tmp/seed.json && cat /tmp/seed.json
```

## Destroy

```bash
cd examples/oracle-rds-source
aws-vault exec data-factory-laa-development -- terraform destroy
```

Verify no tagged resources remain:

```bash
AWS_REGION=eu-west-2 AWS_PAGER="" aws-vault exec data-factory-laa-development -- \
  aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=owner,Values=laa-data-factory \
  --query "ResourceTagMappingList[].ResourceARN" --output table
```

> **Note:** Secrets Manager secrets have a 30-day recovery window by default. After `terraform destroy`, the secrets enter a "scheduled deletion" state and won't appear as active resources, but their ARNs may still show in the tagging API until fully purged. To force immediate deletion, add `recovery_window_in_days = 0` to the secret resources before destroying.

## Troubleshooting

| Problem | Fix |
|---|---|
| `pip: command not found` during apply | Ensure `pip3` is on PATH. The provisioner uses `pip3`. |
| Lambda import error (`base_impl` / circular import) | Layer was built with wrong Python version. Rebuild: `pip3 install oracledb --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.12 --implementation cp -t lambda/layer/python` |
| `ec2:CreateVpc` denied | Expected — sandbox role can't create VPCs. This config uses the shared Modernisation Platform VPC. |
| Terraform credentials error | Use `aws-vault exec`, not `AWS_PROFILE`. Direct SSO profiles don't work with Terraform. |
| `ORA-01031: insufficient privileges` on GRANT | Use `rdsadmin.rdsadmin_util.grant_sys_object` for V$ views and SYS-owned objects (see step 4). |
| Non-ASCII character in SG description | AWS rejects em dashes (`—`). Use ASCII hyphens (`-`) only. |
