# -----------------------------------------------------------------------------
# Oracle RDS test rig for DMS module evaluation (LDF-55)
# Throwaway instance — destroy after testing
# -----------------------------------------------------------------------------

# --- Password generation ---

resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "random_password" "dms_user" {
  length  = 24
  special = false
}

# --- DB Subnet Group ---

resource "aws_db_subnet_group" "oracle" {
  name       = "laa-df-dev-oracle-dms-test"
  subnet_ids = data.aws_subnets.data.ids

  tags = merge(var.tags, {
    Name = "laa-df-dev-oracle-dms-test"
  })
}

# --- Parameter Group (supplemental logging support) ---

resource "aws_db_parameter_group" "oracle" {
  name   = "laa-df-dev-oracle-dms"
  family = "oracle-se2-19"

  parameter {
    name  = "enable_goldengate_replication"
    value = "TRUE"
  }

  tags = merge(var.tags, {
    Name = "laa-df-dev-oracle-dms"
  })
}

# --- Security Group ---

resource "aws_security_group" "oracle" {
  name        = "laa-df-dev-oracle-dms-test"
  description = "Allow DMS replication instance access to Oracle RDS test instance"
  vpc_id      = data.aws_vpc.shared.id

  tags = merge(var.tags, {
    Name = "laa-df-dev-oracle-dms-test"
  })
}

resource "aws_vpc_security_group_ingress_rule" "oracle_from_dms" {
  security_group_id = aws_security_group.oracle.id
  description       = "Oracle access from DMS replication instance"
  cidr_ipv4         = data.aws_vpc.shared.cidr_block
  from_port         = 1521
  to_port           = 1521
  ip_protocol       = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "oracle_outbound" {
  security_group_id = aws_security_group.oracle.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

# --- Oracle RDS Instance ---

resource "aws_db_instance" "oracle" {
  identifier = "laa-df-dev-oracle-dms-test"

  engine         = "oracle-se2"
  engine_version = "19"
  license_model  = "license-included"

  instance_class        = "db.m5.large"
  allocated_storage     = 20
  max_allocated_storage = 0 # no autoscaling — throwaway
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.dms_test.arn

  db_name  = "DMSTEST"
  username = "admin"
  password = random_password.admin.result
  port     = 1521

  db_subnet_group_name   = aws_db_subnet_group.oracle.name
  vpc_security_group_ids = [aws_security_group.oracle.id]
  parameter_group_name   = aws_db_parameter_group.oracle.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = merge(var.tags, {
    Name = "laa-df-dev-oracle-dms-test"
  })
}

# --- Secrets Manager: admin credentials ---

resource "aws_secretsmanager_secret" "oracle_admin" {
  # checkov:skip=CKV2_AWS_57: Automatic rotation not needed for throwaway test instance
  name                    = "laa-df-dev/oracle-dms-test/admin"
  kms_key_id              = aws_kms_key.dms_test.arn
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "laa-df-dev/oracle-dms-test/admin"
  })
}

resource "aws_secretsmanager_secret_version" "oracle_admin" {
  secret_id = aws_secretsmanager_secret.oracle_admin.id
  secret_string = jsonencode({
    host                 = aws_db_instance.oracle.address
    port                 = aws_db_instance.oracle.port
    username             = aws_db_instance.oracle.username
    oracle_password      = random_password.admin.result
    asm_password         = random_password.admin.result
    dbInstanceIdentifier = aws_db_instance.oracle.db_name
  })
}

# --- Secrets Manager: DMS user credentials (to be used after manual user creation) ---

resource "aws_secretsmanager_secret" "oracle_dms_user" {
  # checkov:skip=CKV2_AWS_57: Automatic rotation not needed for throwaway test instance
  name                    = "laa-df-dev/oracle-dms-test/dms-user"
  kms_key_id              = aws_kms_key.dms_test.arn
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "laa-df-dev/oracle-dms-test/dms-user"
  })
}

resource "aws_secretsmanager_secret_version" "oracle_dms_user" {
  secret_id = aws_secretsmanager_secret.oracle_dms_user.id
  secret_string = jsonencode({
    host                 = aws_db_instance.oracle.address
    port                 = aws_db_instance.oracle.port
    username             = "dms_user"
    oracle_password      = random_password.dms_user.result
    asm_password         = random_password.dms_user.result
    dbInstanceIdentifier = aws_db_instance.oracle.db_name
  })
}
