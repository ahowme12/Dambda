# ===================== 리전 간 연결 (VPC Peering) =====================
# 서울 VPC <-> 미국 VPC를 서로 참조해야 해서 environments를 분리하지 않고
# 하나의 root에서 provider alias 두 개로 관리 (remote_state 왕복 없이
# 동일 dependency 그래프 안에서 양쪽 VPC ID를 바로 참조)

# 서울 -> 미국 피어링 요청
resource "aws_vpc_peering_connection" "seoul_to_us" {
  provider = aws.seoul

  vpc_id      = module.network.vpc_id
  peer_vpc_id = module.network_us.vpc_id
  peer_region = var.us_aws_region

  tags = { Name = "${var.region_name}-to-${var.us_region_name}-peering" }
}

# 미국 쪽에서 피어링 수락
resource "aws_vpc_peering_connection_accepter" "us_accept" {
  provider = aws.us_east_1

  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_us.id
  auto_accept               = true

  tags = { Name = "${var.us_region_name}-accept-peering" }
}

# 서울 프라이빗 라우팅 테이블 -> 미국 VPC 대역
resource "aws_route" "seoul_to_us" {
  provider = aws.seoul
  count    = length(module.network.private_route_table_ids)

  route_table_id            = module.network.private_route_table_ids[count.index]
  destination_cidr_block    = var.us_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_us.id
}

# 미국 프라이빗 라우팅 테이블 -> 서울 VPC 대역
resource "aws_route" "us_to_seoul" {
  provider = aws.us_east_1
  count    = length(module.network_us.private_route_table_ids)

  route_table_id            = module.network_us.private_route_table_ids[count.index]
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.seoul_to_us.id

  depends_on = [aws_vpc_peering_connection_accepter.us_accept]
}
