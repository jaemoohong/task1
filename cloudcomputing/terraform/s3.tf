# ---------------------------------------------------------------------------
# S3 (요구사항 6)
# - Bucket Name: wsc-static-<ACCOUNT_ID>
# - 정적 파일은 /static 에 업로드
# - Bucket / Object SSE-KMS 암호화
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "static" {
  bucket = local.bucket_name
  tags   = { Name = local.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static" {
  bucket = aws_s3_bucket.static.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id
  versioning_configuration {
    status = "Enabled"
  }
}

# 제공된 정적 배포 파일을 /static 으로 업로드 한다.
# ./assets/static/ 디렉토리에 제공자료를 그대로 배치한 뒤 적용.
resource "aws_s3_object" "static_files" {
  for_each = fileset("${path.module}/assets/static", "**")

  bucket = aws_s3_bucket.static.id
  key    = "static/${each.value}"
  source = "${path.module}/assets/static/${each.value}"
  # SSE-KMS 객체는 ETag 가 MD5 가 아니므로 etag 대신 source_hash 로 변경 감지
  source_hash            = filemd5("${path.module}/assets/static/${each.value}")
  server_side_encryption = "aws:kms"
  kms_key_id             = aws_kms_key.s3.arn
}

# CloudFront(OAC) 가 객체를 읽을 수 있도록 하는 버킷 정책 (cloudfront.tf 에서 참조)
data "aws_iam_policy_document" "static_bucket" {
  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static" {
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.static_bucket.json
}
