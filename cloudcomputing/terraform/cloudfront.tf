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

# ALB 요청은 캐싱하지 않고 모든 QueryString / 헤더 전달
resource "aws_cloudfront_cache_policy" "no_cache" {
  name        = "wsc-no-cache"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "all"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "all"
    }
    enable_accept_encoding_gzip = false
  }
}

resource "aws_cloudfront_origin_request_policy" "all" {
  name = "wsc-forward-all"
  cookies_config {
    cookie_behavior = "all"
  }
  headers_config {
    header_behavior = "allViewer"
  }
  query_strings_config {
    query_string_behavior = "all"
  }
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
    cache_policy_id          = aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all.id
  }

  # /health -> ALB (ALB 가 403 반환)
  ordered_cache_behavior {
    path_pattern             = "/health"
    target_origin_id         = "app-lb"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = aws_cloudfront_cache_policy.no_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all.id
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
