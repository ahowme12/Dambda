# ALB 보안 그룹에서 인바운드 허용 소스로 사용
output "vpc_link_security_group_id" {
  description = "VPC Link ENI가 사용하는 보안 그룹 ID"
  value       = aws_security_group.vpc_link_sg.id
}

output "api_endpoint" {
  description = "HTTP API 호출 엔드포인트"
  value       = aws_apigatewayv2_stage.default.invoke_url
}
