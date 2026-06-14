# ---------------------------------------------------------------------------
# KMS Customer Managed Keys
# 요구사항 전반에서 S3 / ECR / DynamoDB / EKS Secret / EBS / CloudWatch Logs
# 에 대해 CMK(SSE-KMS) 암호화를 요구한다.
# 운영 편의를 위해 용도별로 키를 분리한다.
# ---------------------------------------------------------------------------

# 공통 정책: 계정 root 전체 권한 + 서비스가 사용할 수 있도록 함
data "aws_iam_policy_document" "kms_default" {
  statement {
    sid       = "EnableRoot"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

# CloudWatch Logs 가 사용할 수 있도록 허용하는 키 정책
data "aws_iam_policy_document" "kms_logs" {
  source_policy_documents = [data.aws_iam_policy_document.kms_default.json]

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${local.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "s3" {
  description             = "wsc S3 SSE-KMS"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "s3" {
  name          = "alias/wsc-s3"
  target_key_id = aws_kms_key.s3.key_id
}

resource "aws_kms_key" "ecr" {
  description             = "wsc ECR encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "ecr" {
  name          = "alias/wsc-ecr"
  target_key_id = aws_kms_key.ecr.key_id
}

resource "aws_kms_key" "dynamodb" {
  description             = "wsc DynamoDB CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "dynamodb" {
  name          = "alias/wsc-dynamodb"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# EKS Secret Envelope Encryption + EBS 볼륨 암호화에 공용으로 사용
resource "aws_kms_key" "eks" {
  description             = "wsc EKS secrets & EBS volume CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}
resource "aws_kms_alias" "eks" {
  name          = "alias/wsc-eks"
  target_key_id = aws_kms_key.eks.key_id
}

resource "aws_kms_key" "logs" {
  description             = "wsc CloudWatch Logs CMK"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_logs.json
}
resource "aws_kms_alias" "logs" {
  name          = "alias/wsc-logs"
  target_key_id = aws_kms_key.logs.key_id
}
