output "ecr_repository_url" {
  description = "backend ECR 레포지토리 URL (enable_backend_app=false면 빈 문자열)"
  value       = var.enable_backend_app ? aws_ecr_repository.backend[0].repository_url : ""
}

output "task_policy_arn" {
  description = "backend 런타임 IAM 정책 ARN (DynamoDB/S3/Lambda/Bedrock 등) - EKS IRSA 롤이 그대로 attach함"
  value       = aws_iam_policy.backend_task_policy.arn
}

output "log_group_name" {
  description = "backend 로그 CloudWatch 로그 그룹 이름 - EKS Fargate aws-logging ConfigMap이 이 그룹으로 라우팅함"
  value       = aws_cloudwatch_log_group.backend_logs.name
}

output "tavily_ssm_parameter_name" {
  description = "Tavily API 키 SSM 파라미터 이름 (없으면 빈 문자열) - modules/eks가 이 값을 읽어 k8s Secret으로 옮김"
  value       = var.tavily_api_key != "" ? aws_ssm_parameter.tavily_api_key[0].name : ""
}
