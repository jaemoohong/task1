# ---------------------------------------------------------------------------
# VPC Interface Endpoints (PrivateLink)
# Workload Subnet 의 라우팅 테이블에는 어떠한 규칙도 둘 수 없으므로 (요구사항 4),
# Gateway Endpoint(S3/DynamoDB) 대신 모든 AWS 서비스 통신을 Interface Endpoint(ENI)
# 로 처리한다. ENI 기반이므로 라우트 테이블이 비어 있어도 통신이 가능하다.
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
  # 완전 프라이빗 워크로드 서브넷에서 EKS / ECR / 모니터링 / 로깅이
  # 정상 동작하기 위해 필요한 인터페이스 엔드포인트 목록
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "s3", # interface 타입 S3 (ECR 레이어 풀 및 정적객체 접근)
    "dynamodb",
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

  workload_subnet_ids = [for k in local.workload_subnet_keys : aws_subnet.this[k].id]
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
