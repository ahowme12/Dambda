# ECS 클러스터 이름 (모니터링 또는 디버깅 시 필요)
output "cluster_name" {
  description = "생성된 ECS 클러스터 이름"
  value       = aws_ecs_cluster.main.name
}

# ECS 서비스 이름 (CI/CD 배포 파이프라인에서 가장 중요)
output "service_name" {
  description = "생성된 ECS 서비스 이름"
  value       = aws_ecs_service.main.name
}

# ECS용 보안 그룹 ID (다른 모듈에서 접근 허용을 위해 필요)
output "ecs_security_group_id" {
  description = "ECS 태스크가 사용하는 보안 그룹 ID"
  value       = aws_security_group.ecs_sg.id
}

# 작업 정의 ARN (최신 배포 버전 확인용)
output "task_definition_arn" {
  description = "최신 배포된 작업 정의 ARN"
  value       = aws_ecs_task_definition.main.arn
}