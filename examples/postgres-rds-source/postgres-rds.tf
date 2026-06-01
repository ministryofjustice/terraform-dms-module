resource "random_password" "admin" {
  length  = 24
  special = false
}

resource "random_password" "dms_user" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.name_prefix}-subnet-group"
  subnet_ids = data.aws_subnets.data.ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-subnet-group"
  })
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.name_prefix}-pg"
  family      = "postgres16"
  description = "Postgres parameter group for DMS logical replication testing"

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-pg"
  })
}

resource "aws_security_group" "postgres" {
  name        = "${var.name_prefix}-sg"
  description = "Allow DMS replication instance access to Postgres RDS test instance"
  vpc_id      = data.aws_vpc.shared.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_dms" {
  security_group_id = aws_security_group.postgres.id
  description       = "Postgres access from DMS replication instance"
  cidr_ipv4         = data.aws_vpc.shared.cidr_block
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "postgres_outbound" {
  security_group_id = aws_security_group.postgres.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = var.tags
}

resource "aws_db_instance" "postgres" {
  identifier = var.name_prefix

  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 0
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.dms_test.arn

  db_name  = "dmstest"
  username = "postgres_admin"
  password = random_password.admin.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name = var.name_prefix
  })
}

resource "aws_secretsmanager_secret" "postgres_admin" {
  name                    = "${var.name_prefix}/admin"
  kms_key_id              = aws_kms_key.dms_test.arn
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${var.name_prefix}/admin"
  })
}

resource "aws_secretsmanager_secret_version" "postgres_admin" {
  secret_id = aws_secretsmanager_secret.postgres_admin.id

  secret_string = jsonencode({
    engine               = "postgres"
    host                 = aws_db_instance.postgres.address
    port                 = aws_db_instance.postgres.port
    dbname               = aws_db_instance.postgres.db_name
    username             = aws_db_instance.postgres.username
    password             = random_password.admin.result
    dbInstanceIdentifier = aws_db_instance.postgres.identifier
  })
}

resource "aws_secretsmanager_secret" "postgres_dms_user" {
  name                    = "${var.name_prefix}/dms-user"
  kms_key_id              = aws_kms_key.dms_test.arn
  recovery_window_in_days = 0

  tags = merge(var.tags, {
    Name = "${var.name_prefix}/dms-user"
  })
}

resource "aws_secretsmanager_secret_version" "postgres_dms_user" {
  secret_id = aws_secretsmanager_secret.postgres_dms_user.id

  secret_string = jsonencode({
    engine               = "postgres"
    host                 = aws_db_instance.postgres.address
    port                 = aws_db_instance.postgres.port
    dbname               = aws_db_instance.postgres.db_name
    username             = "dms_user"
    password             = random_password.dms_user.result
    dbInstanceIdentifier = aws_db_instance.postgres.identifier
  })
}
