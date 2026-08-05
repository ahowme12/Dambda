# VPC 생성
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.region_name}-vpc" }
}

# 퍼블릭 서브넷
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = "${var.aws_region}${var.availability_zones[count.index]}"
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.region_name}-public-subnet-${count.index + 1}" }
}

# 프라이빗 서브넷
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = "${var.aws_region}${var.availability_zones[count.index]}"
  tags              = { Name = "${var.region_name}-private-subnet-${count.index + 1}" }
}

# 인터넷 게이트웨이
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.region_name}-igw" }
}

# 퍼블릭 라우팅 테이블
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${var.region_name}-public-rt" }
}

# 퍼블릭 서브넷 연결
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway와 EIP (프라이빗 통신용)
locals {
  # null이면 기존 동작(AZ별 1개) 유지
  nat_gateway_count = var.nat_gateway_count != null ? var.nat_gateway_count : length(var.public_subnets)
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = { Name = "${var.region_name}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "nat" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # 해당 AZ의 퍼블릭 서브넷에 배치 (1개면 서브넷[0])

  tags = { Name = "${var.region_name}-nat-gw-${count.index + 1}" }
}

# 프라이빗 라우팅 테이블. NAT가 1개뿐이면 모든 라우팅 테이블이 그 하나를 같이 씀,
# 0개면(DR 등 아무것도 안 도는 리전) 인터넷 경로 자체를 안 만듦
resource "aws_route_table" "private" {
  count  = length(var.private_subnets)
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = local.nat_gateway_count > 0 ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.nat[min(count.index, local.nat_gateway_count - 1)].id
    }
  }

  tags = { Name = "${var.region_name}-private-rt-${count.index + 1}" }
}

# 프라이빗 서브넷과 라우팅 테이블 연결
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# API Gateway Endpoint용 보안 그룹
resource "aws_security_group" "api_gateway_endpoint_sg" {
  name        = "${var.region_name}-api-gateway-endpoint-sg"
  description = "Security group for API Gateway VPC Endpoint"
  vpc_id      = aws_vpc.main.id

  # ECS 서비스(또는 해당 VPC 대역)에서 443 포트 접근 허용
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.region_name}-api-gateway-endpoint-sg" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id # 프라이빗 라우팅 테이블에 S3 경로 추가

  tags = { Name = "${var.region_name}-s3-endpoint" }
}

# DynamoDB Gateway VPC Endpoint
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  # 프라이빗 라우팅 테이블에 DynamoDB 경로 추가
  route_table_ids = aws_route_table.private[*].id

  tags = { Name = "${var.region_name}-dynamodb-endpoint" }
}

# ECR DKR Endpoint (이미지 Pull)
resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.api_gateway_endpoint_sg.id]

  tags = { Name = "${var.region_name}-ecr-dkr-endpoint" }
}

# ECR API Endpoint (이미지 메타데이터 조회)
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.api_gateway_endpoint_sg.id]

  tags = { Name = "${var.region_name}-ecr-api-endpoint" }
}

# CloudWatch Logs Endpoint (로그 전송)
resource "aws_vpc_endpoint" "logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.api_gateway_endpoint_sg.id]

  tags = { Name = "${var.region_name}-logs-endpoint" }
}