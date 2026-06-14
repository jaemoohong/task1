# ---------------------------------------------------------------------------
# WAF (요구사항 13)
# - wsc-waf : CloudFront 에 연결 (scope=CLOUDFRONT 이므로 us-east-1 provider 사용)
# - POST Method 요청 Body 에 "admin" 또는 "sysop" 문자열 포함 시 Block
# ---------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "wsc" {
  provider = aws.use1
  name     = "wsc-waf"
  scope    = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "block-admin-sysop-in-post-body"
    priority = 1

    action {
      block {}
    }

    statement {
      and_statement {
        # POST Method 인 경우
        statement {
          byte_match_statement {
            positional_constraint = "EXACTLY"
            search_string         = "POST"
            field_to_match {
              method {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
        # Body 에 admin 또는 sysop 포함
        statement {
          or_statement {
            statement {
              byte_match_statement {
                positional_constraint = "CONTAINS"
                search_string         = "admin"
                field_to_match {
                  body {}
                }
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
            statement {
              byte_match_statement {
                positional_constraint = "CONTAINS"
                search_string         = "sysop"
                field_to_match {
                  body {}
                }
                text_transformation {
                  priority = 0
                  type     = "LOWERCASE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "block-admin-sysop"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "wsc-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "wsc-waf" }
}
