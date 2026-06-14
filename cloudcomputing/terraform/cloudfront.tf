# ---------------------------------------------------------------------------
# CloudFront (요구사항 14)
# - wsc-cdn : Origin = S3(OAC) + 내부 ALB(VPC Origin)
# - S3 정적 콘텐츠는 캐싱, ALB 요청은 캐싱하지 않고 QueryString 전부 전달
# - HTTP -> HTTPS 리다이렉트
# - IPv6 비활성화, CloudFront 1개만 생성
# - 전 세계 빠른 접근을 위해 PriceClass_All (모든 엣지)
# - WAF(wsc-waf) 연결
#
# 내부(Private) ALB 에 접근하기 위해 CloudFront VPC Origin 을 사용한다.
# (외부에 ALB 를 노출하지 않으면서 CloudFront 만 접근 가능 → ZTNA)
# ---------------------------------------------------------------------------

# S3 용 Origin Access Control
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "wsc-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# 내부 ALB 를 가리키는 VPC Origin
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "wsc-app-lb-origin"
    arn                    = aws_lb.app.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

# ALB 요청은 캐싱하지 않고 모든 QueryString / 헤더 / 쿠키를 Origin 으로 전달.
# 캐싱 비활성 정책에서는 Cache Key 에 Cookie/QueryString 을 넣을 수 없으므로
# AWS 관리형 정책을 사용한다.
#   - CachingDisabled            : 4135ea2d-6df8-44a3-9df3-4b5a84be39ad
#   - AllViewerExceptHostHeader  : b689b0a8-53d0-40ab-baf2-68738e2966ac (QueryString/쿠키/헤더 전부 전달)
locals {
  cache_policy_caching_disabled = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  orp_all_viewer_except_host    = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = false # 채점 오동작 방지 (요구사항 14)
  comment         = "wsc-cdn"
  price_class     = "PriceClass_All"
  web_acl_id      = aws_wafv2_web_acl.wsc.arn

  # ----- S3 Origin -----
  origin {
    origin_id                = "s3-static"
    domain_name              = aws_s3_bucket.static.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ----- ALB(VPC Origin) -----
  origin {
    origin_id   = "app-lb"
    domain_name = aws_lb.app.dns_name

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.alb.id
    }
  }

  # 기본 동작: 정적 콘텐츠 -> S3 (캐싱)
  default_cache_behavior {
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https" # HTTP -> HTTPS
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  }

  # API(/v1/*) -> ALB (캐싱 없음, QueryString 전달)
  ordered_cache_behavior {
    path_pattern             = "/v1/*"
    target_origin_id         = "app-lb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  # /health -> ALB (ALB 가 403 반환)
  ordered_cache_behavior {
    path_pattern             = "/health"
    target_origin_id         = "app-lb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = local.orp_all_viewer_except_host
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "wsc-cdn" }
}
