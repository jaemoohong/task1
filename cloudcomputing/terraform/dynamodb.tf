# ---------------------------------------------------------------------------
# DynamoDB (요구사항 8)
# - Table Name: wsc-table
# - Partition Key: client_id (String)
# - Customer Managed Key 암호화
# 비키 속성(username/email/concert_name)은 스키마리스이므로 정의 불필요.
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "wsc" {
  name         = "wsc-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "client_id"

  attribute {
    name = "client_id"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = { Name = "wsc-table" }
}
