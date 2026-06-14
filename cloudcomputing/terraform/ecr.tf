# ---------------------------------------------------------------------------
# ECR (요구사항 7)
# - Name: wsc-repo
# - KMS 암호화 + Push 시 취약점 스캔 (scan on push)
# - 이미지 태그: v1.0.0 (push 는 Bastion/CI 에서 수행)
#   이미지 경량화(<=8MB), curl 포함은 app/Dockerfile 참고
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "repo" {
  name                 = "wsc-repo"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr.arn
  }

  tags = { Name = "wsc-repo" }
}

# Enhanced scanning(취약점 상세 분석) 활성화
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "wsc-repo"
      filter_type = "WILDCARD"
    }
  }
}
