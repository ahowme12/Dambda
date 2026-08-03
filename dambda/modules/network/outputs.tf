# VPC ID 노출
output "vpc_id" {
  description = "생성된 VPC의 ID"
  value       = aws_vpc.main.id
}

# 퍼블릭 서브넷 ID 리스트 노출
output "public_subnet_ids" {
  description = "퍼블릭 서브넷들의 ID 리스트"
  value       = aws_subnet.public[*].id
}

# 프라이빗 서브넷 ID 리스트 노출
output "private_subnet_ids" {
  description = "프라이빗 서브넷들의 ID 리스트"
  value       = aws_subnet.private[*].id
}

# 프라이빗 라우팅 테이블 ID 리스트 (NAT 게이트웨이와 매칭용)
output "private_route_table_ids" {
  description = "프라이빗 라우팅 테이블 ID 리스트"
  value       = aws_route_table.private[*].id
}

# VPC CIDR (피어링 할 때 상대방 CIDR 알기 위해 필요)
output "vpc_cidr" {
  description = "VPC의 CIDR 블록"
  value       = aws_vpc.main.cidr_block
}

# 나중에 ECS 모듈에서 엔드포인트 보안 그룹 규칙을 수정할 때 필요할 수 있음
output "ecs_security_group_id" {
  value = aws_security_group.api_gateway_endpoint_sg.id
}