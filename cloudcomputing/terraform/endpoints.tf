# ---------------------------------------------------------------------------
# VPC Interface Endpoints (PrivateLink)
# Workload Subnet 의 라우팅 테이블에는 어떠한 규칙도 둘 수 없으므로 (요구사항 4),
# Gateway Endpoint(S3/DynamoDB) 대신 모든 AWS 서비스 통신을 Interface Endpoint(ENI)
# 로 처리한다. ENI 기반이므로 라우트 테이블이 비어 있어도 통신이 가능하다.
#
# 주의:
# - S3 인터페이스 엔드포인트는 Native Private DNS 활성화 시 S3 Gateway 엔드포인트를
#   요구한다(라우트 추가됨). 따라서 private_dns_enabled=false 로 두고 Route53
#   Private Hosted Zone 으로 기본 도메인을 인터페이스 엔드포인트에 매핑한다.
# - DynamoDB 인터페이스 엔드포인트는 Private DNS 를 제공하지 않으므로 동일하게
#   Private Hosted Zone 으로 매핑한다.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpce" {
  name        = "wsc-vpce-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "wsc-vpce-sg" }
}

locals {
  workload_subnet_ids = [for k in local.workload_subnet_keys : aws_subnet.this[k].id]

  # Native Private DNS 를 지원하는 서비스 (그대로 기본 도메인으로 해석됨)
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "logs",
    "ec2",
    "elasticloadbalancing",
    "autoscaling",
    "eks",
    "eks-auth",
    "kms",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.workload_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = { Name = "wsc-vpce-${each.key}" }
}

# ----- S3 / DynamoDB: Interface Endpoint (Private DNS 비활성) -----
resource "aws_vpc_endpoint" "s3" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.workload_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = { Name = "wsc-vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.workload_subnet_ids
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = false

  tags = { Name = "wsc-vpce-dynamodb" }
}

# ----- Route53 Private Hosted Zone 으로 기본 도메인을 인터페이스 EP 로 매핑 -----
# S3
resource "aws_route53_zone" "s3" {
  name = "s3.${var.region}.amazonaws.com"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  comment = "wsc - resolve S3 to interface endpoint"
}

resource "aws_route53_record" "s3_apex" {
  zone_id = aws_route53_zone.s3.zone_id
  name    = "s3.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.s3.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.s3.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# 가상 호스팅 방식(bucket.s3.region.amazonaws.com) 대응 와일드카드
resource "aws_route53_record" "s3_wildcard" {
  zone_id = aws_route53_zone.s3.zone_id
  name    = "*.s3.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.s3.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.s3.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}

# DynamoDB
resource "aws_route53_zone" "dynamodb" {
  name = "dynamodb.${var.region}.amazonaws.com"
  vpc {
    vpc_id = aws_vpc.this.id
  }
  comment = "wsc - resolve DynamoDB to interface endpoint"
}

resource "aws_route53_record" "dynamodb_apex" {
  zone_id = aws_route53_zone.dynamodb.zone_id
  name    = "dynamodb.${var.region}.amazonaws.com"
  type    = "A"
  alias {
    name                   = aws_vpc_endpoint.dynamodb.dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.dynamodb.dns_entry[0].hosted_zone_id
    evaluate_target_health = false
  }
}
