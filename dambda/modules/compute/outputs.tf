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

# EKS 모듈이 동일한 backend 이미지를 그대로 재사용하기 위한 output
output "ecr_repository_url" {
  description = "backend ECR 레포지토리 URL (enable_backend_app=false면 빈 문자열)"
  value       = var.enable_backend_app ? aws_ecr_repository.backend[0].repository_url : ""
}

# EKS IRSA 롤이 ECS 태스크와 동일한 런타임 권한을 쓰기 위한 output (정책 JSON 중복 방지)
output "task_policy_arn" {
  description = "ECS 태스크 런타임 IAM 정책 ARN (DynamoDB/S3/Lambda/Bedrock 등)"
  value       = aws_iam_policy.ecs_task_policy.arn
}