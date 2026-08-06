variable "region_name" {
  description = "리소스 이름 태그용 접두어"
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

variable "vpc_id" {
  description = "ECS가 배치될 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "ECS 서비스가 배포될 프라이빗 서브넷 ID 리스트"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "alb_security_group_id" {
  description = "ALB의 보안 그룹 ID (ECS 보안 그룹에서 허용하기 위함)"
  type        = string
}

variable "target_group_arn" {
  description = "ALB 대상 그룹 ARN (ECS 서비스 등록용)"
  type        = string
}

variable "container_port" {
  description = "컨테이너가 리스닝할 포트"
  type        = number
  default     = 80
}

variable "desired_count" {
  description = "평소 유지할 ECS 태스크 개수 (pilot light DR 리전은 0으로 설정)"
  type        = number
  default     = 2
}

variable "autoscaling_min_capacity" {
  description = "오토스케일링 최소 태스크 개수 (pilot light DR 리전은 0으로 설정)"
  type        = number
  default     = 2
}

variable "autoscaling_max_capacity" {
  description = "오토스케일링 최대 태스크 개수 (재해 전환 시 실제로 받을 트래픽 기준)"
  type        = number
  default     = 5
}

variable "dynamodb_table_arns" {
  description = "ECS 태스크가 접근할 DynamoDB 테이블/GSI ARN 목록 (같은 리전의 홈 테이블 또는 replica)"
  type        = list(string)
}

variable "lambda_invoke_arns" {
  description = "ECS 태스크가 호출할 수 있는 Lambda ARN 목록 (예: 번역 Lambda)"
  type        = list(string)
}

# ===================== backend/(Express) 앱 관련 =====================
# false면 기존 placeholder 컨테이너 유지 - pilot light DR 리전(compute_us)처럼 아직
# 이 앱을 확장하지 않은 곳에서 씀. true인 호출부만 아래 값들을 실제로 채워서 넘기면 됨.
variable "enable_backend_app" {
  description = "ECR에 올라간 실제 backend 이미지로 배포할지 (false면 node:20-alpine placeholder 유지)"
  type        = bool
  default     = true
}

variable "user_pool_id" {
  type    = string
  default = ""
}

variable "user_pool_client_id" {
  type    = string
  default = ""
}

# 회원가입/로그인/내정보 조회(backend/src/services/cognito.js)에서 Admin* API를 태스크
# IAM 자격증명으로 직접 호출하므로 IAM 정책에 이 ARN이 필요함 (id만으로는 스코프 불가)
variable "user_pool_arn" {
  type    = string
  default = ""
}

variable "dynamodb_table_name" {
  description = "backend가 회원 프로필 조회에 쓰는 테이블 이름 (dynamodb 모듈의 user_profiles)"
  type        = string
  default     = ""
}

variable "product_likes_table_name" {
  type    = string
  default = ""
}

variable "product_reviews_table_name" {
  type    = string
  default = ""
}

# Get/Scan만 허용(쓰기는 시딩 스크립트 전담)이라 dynamodb_table_arns 배열에 안 섞고 따로 받음
variable "product_catalog_table_name" {
  type    = string
  default = ""
}

variable "product_catalog_table_arn" {
  type    = string
  default = ""
}

variable "review_photos_bucket_name" {
  type    = string
  default = ""
}

variable "review_photos_bucket_arn" {
  type    = string
  default = ""
}

variable "review_photos_bucket_domain" {
  type    = string
  default = ""
}

variable "review_moderation_lambda_name" {
  type    = string
  default = ""
}

variable "bedrock_model_id" {
  description = "상품 Q&A(backend/src/services/bedrock.js)에 쓸 Bedrock 모델/추론 프로파일 ID. 콘솔에서 Nova 모델 액세스를 먼저 활성화해야 하고, 리전에 따라 온디맨드 직접 호출 대신 cross-region inference profile ID(예: apac.*)가 필요할 수 있어 실제 값은 콘솔에서 확인 후 조정 필요"
  type        = string
  default     = ""
}

variable "tavily_api_key" {
  description = "backend/src/services/websearch.js의 tool-use 웹검색용 Tavily API 키. 값이 없으면 SSM 파라미터/권한을 아예 안 만들고, 백엔드도 web_search 도구 자체를 Nova에게 안 줌"
  type        = string
  default     = ""
  sensitive   = true
}