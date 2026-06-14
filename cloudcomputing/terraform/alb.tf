# ---------------------------------------------------------------------------
# App Load Balancer (요구사항 12.1)
# - wsc-app-lb : L7 / Internal (Private Subnet), 외부 직접 접근 불가
# - CloudFront 를 통해서만 접근 (CloudFront origin-facing prefix list 로 SG 제한)
# - /health           -> 403 "Restrict access to api"
# - /v1/book  GET      -> Lambda(wsc-get-table-function)
# - /v1/book  POST     -> wsc Namespace 의 앱 Pod (IP TargetGroup, TGB 로 등록)
# - 그 외 모든 경로     -> 404 "Contents Not Found"
#
# 앱 Pod 등록은 k8s/app/targetgroupbinding.yaml(AWS LB Controller CRD) 가
# 아래 app TargetGroup ARN(outputs) 에 Pod IP 를 동적으로 바인딩한다.
# ---------------------------------------------------------------------------

# CloudFront 의 origin-facing 관리형 prefix list (CloudFront 에서만 인입 허용)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "app_lb" {
  name        = "wsc-app-lb-sg"
  description = "App ALB - allow 80 from CloudFront only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront edge only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-app-lb-sg" }
}

resource "aws_lb" "app" {
  name               = "wsc-app-lb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.app_lb.id]
  subnets            = [for k in local.private_subnet_keys : aws_subnet.this[k].id]

  tags = { Name = "wsc-app-lb" }
}

# ----- App Pod 용 IP TargetGroup (TargetGroupBinding 으로 Pod IP 등록) -----
resource "aws_lb_target_group" "app" {
  name        = "wsc-app-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.this.id

  health_check {
    path                = "/health"
    port                = "8080"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    matcher             = "200"
  }

  tags = { Name = "wsc-app-tg" }
}

# ----- Lambda TargetGroup -----
resource "aws_lambda_permission" "alb" {
  statement_id  = "AllowALBInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_table.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}

resource "aws_lb_target_group" "lambda" {
  name        = "wsc-lambda-tg"
  target_type = "lambda"

  tags = { Name = "wsc-lambda-tg" }
}

resource "aws_lb_target_group_attachment" "lambda" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.get_table.arn
  depends_on       = [aws_lambda_permission.alb]
}

# ----- Listener (80) -----
resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # 기본: 명시되지 않은 모든 경로 -> 404 "Contents Not Found"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Contents Not Found"
      status_code  = "404"
    }
  }
}

# /health -> 403 "Restrict access to api" (최우선)
resource "aws_lb_listener_rule" "health_block" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 10

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "Restrict access to api"
      status_code  = "403"
    }
  }

  condition {
    path_pattern {
      values = ["/health"]
    }
  }
}

# GET /v1/book -> Lambda
resource "aws_lb_listener_rule" "get_book" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
  condition {
    http_request_method {
      values = ["GET"]
    }
  }
}

# POST /v1/book -> App Pod
resource "aws_lb_listener_rule" "post_book" {
  listener_arn = aws_lb_listener.app.arn
  priority     = 21

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  condition {
    path_pattern {
      values = ["/v1/book"]
    }
  }
  condition {
    http_request_method {
      values = ["POST"]
    }
  }
}
