variable "region_name" {
  type = string
}

variable "vpc_id" {
  description = "VPC Link ENI 보안 그룹이 생성될 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "VPC Link ENI가 배치될 프라이빗 서브넷 ID 리스트"
  type        = list(string)
}

variable "alb_listener_arn" {
  description = "내부 ALB HTTP 리스너 ARN (HTTP_PROXY 통합 대상)"
  type        = string
}

variable "cors_allowed_origins" {
  description = "브라우저에서 API 호출을 허용할 Origin 목록 (웹이 S3/CloudFront에서 API Gateway를 직접 호출하므로 필요)"
  type        = list(string)
}

variable "cognito_issuer_url" {
  description = "JWT Authorizer의 issuer (Cognito User Pool 엔드포인트)"
  type        = string
}

variable "cognito_app_client_id" {
  description = "JWT Authorizer의 audience로 사용할 Cognito App Client ID"
  type        = string
}

variable "require_auth" {
  description = "true면 $default 라우트 전체에 Cognito JWT 인증을 요구함 (경로별 공개/비공개 분리는 아직 없음)"
  type        = bool
  default     = true
}