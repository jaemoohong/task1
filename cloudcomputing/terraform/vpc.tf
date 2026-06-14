# ---------------------------------------------------------------------------
# VPC (Reference01)
# - wsc-vpc 10.0.0.0/16
# - public  : IGW 로 직접 인터넷 (Direct Access)
# - private : NAT 경유 아웃바운드 (Internal Access)
# - workload: 라우팅 테이블에 어떠한 규칙도 없음 (No Internet)
#             AWS 서비스 통신은 오직 Interface VPC Endpoint 로만 수행 (endpoints.tf)
# ---------------------------------------------------------------------------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "wsc-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "wsc-igw" }
}

resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.tier == "public"

  tags = merge(
    { Name = each.key },
    # AWS Load Balancer Controller 의 서브넷 자동 디스커버리용 태그
    each.value.tier == "public" ? {
      "kubernetes.io/role/elb"                    = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
    each.value.tier == "private" ? {
      "kubernetes.io/role/internal-elb"           = "1"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
    each.value.tier == "workload" ? {
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    } : {},
  )
}

# ----- Public Route Table : IGW -----
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "wsc-public-rtb" }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = toset(local.public_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

# ----- NAT Gateway (private 아웃바운드) -----
resource "aws_eip" "nat" {
  for_each = toset(local.private_subnet_keys)
  domain   = "vpc"
  tags     = { Name = "wsc-nat-eip-${each.key}" }
}

# NAT 는 public 서브넷(같은 AZ)에 배치한다. AZ 매칭을 위해 public 키를 az 기준으로 매핑.
locals {
  public_by_az = { for k in local.public_subnet_keys : var.subnets[k].az => k }
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.private_subnet_keys)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[local.public_by_az[var.subnets[each.key].az]].id
  tags          = { Name = "wsc-nat-${each.key}" }
  depends_on    = [aws_internet_gateway.this]
}

# ----- Private Route Tables : per-AZ NAT (Reference01: private-a-rtb / private-c-rtb) -----
resource "aws_route_table" "private" {
  for_each = toset(local.private_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${each.key}-rtb" }
}

resource "aws_route" "private_nat" {
  for_each               = toset(local.private_subnet_keys)
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each       = toset(local.private_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

# ----- Workload Route Tables : 규칙 없음 (No Internet) -----
# 라우트(aws_route) 를 의도적으로 생성하지 않는다. local 라우트만 암묵적으로 존재.
# AWS 서비스 접근은 Interface Endpoint(ENI) 로만 이루어지므로 라우트 테이블이 비어있어도 통신 가능.
resource "aws_route_table" "workload" {
  for_each = toset(local.workload_subnet_keys)
  vpc_id   = aws_vpc.this.id
  tags     = { Name = "${each.key}-rtb" }
}

resource "aws_route_table_association" "workload" {
  for_each       = toset(local.workload_subnet_keys)
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.workload[each.key].id
}
