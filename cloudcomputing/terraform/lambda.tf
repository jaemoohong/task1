# ---------------------------------------------------------------------------
# Lambda (요구사항 15)
# - Name: wsc-get-table-function
# - Private Subnet 내 운용 (VPC 연결), DynamoDB 조회
# - CloudFront -> app-lb -> Lambda(ALB Target) 경로로 호출됨 (alb.tf)
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "wsc-get-table-function-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_perms" {
  statement {
    sid       = "DynamoRead"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.wsc.arn]
  }
  statement {
    sid       = "KmsDecrypt"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.dynamodb.arn]
  }
  statement {
    sid = "VpcEni"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

resource "aws_security_group" "lambda" {
  name        = "wsc-lambda-sg"
  description = "Lambda ENI SG"
  vpc_id      = aws_vpc.this.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-lambda-sg" }
}

resource "aws_lambda_function" "get_table" {
  function_name    = "wsc-get-table-function"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      TABLE_NAME      = aws_dynamodb_table.wsc.name
      AWS_REGION_NAME = var.region
    }
  }

  # Private Subnet 내에서 운용 (요구사항 15)
  vpc_config {
    subnet_ids         = [for k in local.private_subnet_keys : aws_subnet.this[k].id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = { Name = "wsc-get-table-function" }
}
