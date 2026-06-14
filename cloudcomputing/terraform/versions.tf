terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

# 기본 프로바이더 - 모든 리소스는 서울(ap-northeast-2) 리전에 생성 (유의사항 8)
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "wsc"
      ManagedBy = "terraform"
    }
  }
}

# CloudFront 에 연결되는 WAF(WebACL, scope=CLOUDFRONT) 와
# CloudFront 관련 글로벌 리소스는 반드시 us-east-1 에 생성해야 한다.
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "wsc"
      ManagedBy = "terraform"
    }
  }
}
