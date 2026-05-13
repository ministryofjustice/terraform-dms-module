# -----------------------------------------------------------------------------
# Lambda function to execute SQL against Oracle RDS (connectivity workaround)
# Deployed in the same VPC/subnets as RDS — invoke from CLI
# Destroy after setup is complete
# -----------------------------------------------------------------------------

data "archive_file" "oracle_sql_runner" {
  type        = "zip"
  source_file = "${path.module}/lambda/oracle_sql_runner.py"
  output_path = "${path.module}/lambda/oracle_sql_runner.zip"
}

# --- Lambda Layer for oracledb ---

resource "null_resource" "build_oracledb_layer" {
  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${path.module}/lambda/layer
      mkdir -p ${path.module}/lambda/layer/python
      pip3 install oracledb --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.12 --implementation cp -t ${path.module}/lambda/layer/python --quiet
    EOT
  }

  triggers = {
    always_run = timestamp()
  }
}

data "archive_file" "oracledb_layer" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/layer"
  output_path = "${path.module}/lambda/oracledb_layer.zip"

  depends_on = [null_resource.build_oracledb_layer]
}

resource "aws_lambda_layer_version" "oracledb" {
  filename            = data.archive_file.oracledb_layer.output_path
  source_code_hash    = data.archive_file.oracledb_layer.output_base64sha256
  layer_name          = "${var.name_prefix}-oracledb-thin"
  compatible_runtimes = ["python3.12"]

  depends_on = [data.archive_file.oracledb_layer]
}

# --- IAM Role ---

resource "aws_iam_role" "lambda_sql_runner" {
  name = "${var.name_prefix}-oracle-sql-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_sql_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_sql_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- Security Group ---

resource "aws_security_group" "lambda_sql_runner" {
  name        = "${var.name_prefix}-oracle-sql-runner"
  description = "Lambda SQL runner - outbound to Oracle RDS"
  vpc_id      = data.aws_vpc.shared.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-oracle-sql-runner"
  })
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_oracle" {
  security_group_id = aws_security_group.lambda_sql_runner.id
  description       = "Oracle access"
  cidr_ipv4         = data.aws_vpc.shared.cidr_block
  from_port         = 1521
  to_port           = 1521
  ip_protocol       = "tcp"

  tags = var.tags
}

# --- Lambda Function ---

resource "aws_lambda_function" "oracle_sql_runner" {
  # checkov:skip=CKV_AWS_272: Code signing not needed for throwaway test Lambda
  # checkov:skip=CKV_AWS_116: DLQ not needed for throwaway test Lambda
  # checkov:skip=CKV_AWS_173: Environment variables don't contain secrets
  function_name    = "${var.name_prefix}-oracle-sql-runner"
  role             = aws_iam_role.lambda_sql_runner.arn
  handler          = "oracle_sql_runner.handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256
  filename         = data.archive_file.oracle_sql_runner.output_path
  source_code_hash = data.archive_file.oracle_sql_runner.output_base64sha256
  layers           = [aws_lambda_layer_version.oracledb.arn]

  vpc_config {
    subnet_ids         = data.aws_subnets.data.ids
    security_group_ids = [aws_security_group.lambda_sql_runner.id]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-oracle-sql-runner"
  })
}
