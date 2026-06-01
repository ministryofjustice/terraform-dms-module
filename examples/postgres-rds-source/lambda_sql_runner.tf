locals {
  postgres_sql_runner_build_dir = "${path.module}/build/postgres_sql_runner"
  postgres_sql_runner_zip       = "${path.module}/build/postgres_sql_runner.zip"
}

resource "aws_security_group" "postgres_sql_runner" {
  name        = "${var.name_prefix}-sql-runner-sg"
  description = "Security group for Postgres SQL runner Lambda"
  vpc_id      = data.aws_vpc.shared.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-sql-runner-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "postgres_sql_runner_to_postgres" {
  security_group_id            = aws_security_group.postgres_sql_runner.id
  referenced_security_group_id = aws_security_group.postgres.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow SQL runner Lambda to connect to Postgres"
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_sql_runner" {
  security_group_id            = aws_security_group.postgres.id
  referenced_security_group_id = aws_security_group.postgres_sql_runner.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Allow SQL runner Lambda to connect to Postgres"

  tags = var.tags
}

resource "aws_iam_role" "postgres_sql_runner" {
  name = "${var.name_prefix}-sql-runner"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "postgres_sql_runner_basic" {
  role       = aws_iam_role.postgres_sql_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "postgres_sql_runner_vpc" {
  role       = aws_iam_role.postgres_sql_runner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "null_resource" "postgres_sql_runner_package" {
  triggers = {
    source_hash = filesha256("${path.module}/lambda/postgres_sql_runner.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      rm -rf ${local.postgres_sql_runner_build_dir} ${local.postgres_sql_runner_zip}
      mkdir -p ${local.postgres_sql_runner_build_dir}
      cp ${path.module}/lambda/postgres_sql_runner.py ${local.postgres_sql_runner_build_dir}/
      python3 -m pip install --platform manylinux2014_x86_64 --implementation cp --python-version 3.12 --only-binary=:all: --target ${local.postgres_sql_runner_build_dir} "psycopg[binary]==3.2.3"
    EOT
  }
}

data "archive_file" "postgres_sql_runner" {
  type        = "zip"
  source_dir  = local.postgres_sql_runner_build_dir
  output_path = local.postgres_sql_runner_zip

  depends_on = [
    null_resource.postgres_sql_runner_package
  ]
}

resource "aws_lambda_function" "postgres_sql_runner" {
  # checkov:skip=CKV_AWS_272: Code signing not needed for throwaway test Lambda
  # checkov:skip=CKV_AWS_116: DLQ not needed for throwaway test Lambda
  # checkov:skip=CKV_AWS_173: Environment variables don't contain secrets
  function_name = "${var.name_prefix}-sql-runner"
  role          = aws_iam_role.postgres_sql_runner.arn
  handler       = "postgres_sql_runner.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.postgres_sql_runner.output_path
  source_code_hash = data.archive_file.postgres_sql_runner.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.data.ids
    security_group_ids = [aws_security_group.postgres_sql_runner.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.postgres_sql_runner_basic,
    aws_iam_role_policy_attachment.postgres_sql_runner_vpc,
  ]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-sql-runner"
  })
}
