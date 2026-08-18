variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "ecr_repository_name" {
  description = "백엔드 ECR 레포지토리 이름. ECR 네이티브 리플리케이션은 같은 이름의 레포로만 복제되므로, DR 리전은 이걸 소스 리전과 동일한 값으로 넘겨야 함 (region_name 접두어를 그대로 쓰면 리전마다 이름이 달라져서 복제가 끊김)"
  type        = string
  default     = ""
}

locals {
  ecr_repository_name = var.ecr_repository_name != "" ? var.ecr_repository_name : "${var.region_name}-backend"
}

# false면 이 리전은 아직 backend 앱 범위 밖 - ECR/IAM 정책 자체를 안 만듦. compute 모듈
# 시절과 동일한 성격의 게이팅(현재는 두 리전 다 true로 씀 - us-east-1도 향후 EKS DR을
# 붙일 때를 대비해 ECR 복제 대상/로그 그룹을 미리 갖춰둠)
variable "enable_backend_app" {
  description = "이 리전에 backend 앱용 ECR/IAM 정책/로그 그룹을 만들지 여부"
  type        = bool
  default     = true
}

variable "dynamodb_table_arns" {
  description = "backend가 접근할 DynamoDB 테이블/GSI ARN 목록 (같은 리전의 홈 테이블 또는 replica)"
  type        = list(string)
}

variable "lambda_invoke_arns" {
  description = "backend가 호출할 수 있는 Lambda ARN 목록 (예: 번역 Lambda)"
  type        = list(string)
}

variable "user_pool_arn" {
  description = "backend가 Admin* Cognito API를 호출하기 위한 User Pool ARN"
  type        = string
  default     = ""
}

variable "product_catalog_table_arn" {
  type    = string
  default = ""
}

variable "review_photos_bucket_arn" {
  type    = string
  default = ""
}

variable "quarantine_bucket_arn" {
  type    = string
  default = ""
}

variable "review_moderation_queue_arn" {
  type    = string
  default = ""
}

variable "moderation_events_table_arn" {
  type    = string
  default = ""
}

variable "product_images_bucket_arn" {
  type    = string
  default = ""
}

# ADOT 사이드카(EKS 파드에서 직접 구성됨)의 aps:RemoteWrite 권한 - IRSA가 이 모듈의
# task_policy_arn을 그대로 attach하므로 여기서 같이 관리함(ECS 시절 ecs_task_policy와 동일 위치)
variable "enable_prometheus" {
  description = "AMP로 메트릭을 보낼 권한(aps:RemoteWrite)을 task 정책에 포함할지 여부"
  type        = bool
  default     = false
}

variable "prometheus_workspace_arn" {
  type    = string
  default = ""
}

# backend/src/services/websearch.js의 tool-use 웹검색용 Tavily API 키. 값이 없으면 SSM
# 파라미터 자체를 안 만듦(EKS 파드도 web_search 도구를 안 받음)
variable "tavily_api_key" {
  description = "Tavily API 키 (SSM SecureString으로 저장)"
  type        = string
  default     = ""
  sensitive   = true
}
