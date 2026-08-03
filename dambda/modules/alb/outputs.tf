# ECS 보안 그룹에서 ALB 트래픽을 허용하기 위해 필요
output "security_group_id" {
  description = "ALB가 사용하는 보안 그룹 ID"
  value       = aws_security_group.alb_sg.id
}

# ECS 서비스가 로드밸런서에 등록될 때 필요
output "target_group_arn" {
  description = "ALB와 연결된 대상 그룹 ARN"
  value       = aws_lb_target_group.main.arn
}

output "dns_name" {
  description = "ALB의 DNS 이름"
  value       = aws_lb.main.dns_name
}

# API Gateway VPC Link 통합(integration)에서 필요
output "listener_arn" {
  description = "ALB HTTP 리스너 ARN"
  value       = aws_lb_listener.http.arn
}
