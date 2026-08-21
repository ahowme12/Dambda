variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "aws_region" {
  description = "User Pool이 생성되는 리전 (JWT issuer URL 조립용)"
  type        = string
}

variable "dynamodb_users_table_name" {
  description = "가입 완료 시 프로필을 기록할 DynamoDB Users 테이블 이름"
  type        = string
}

variable "dynamodb_users_table_arn" {
  description = "Post Confirmation Lambda가 PutItem 할 Users 테이블 ARN"
  type        = string
}

# 비워두면(기본값) Google 로그인 IdP 자체를 안 만듦 - Google Cloud Console에서 OAuth 클라이언트를
# 발급받아야 하는 외부 의존값이라, 없어도 나머지 Cognito 기능(이메일/비번 로그인)은 그대로 동작함
variable "google_oauth_client_id" {
  type     = string
  default  = ""
  nullable = false
}

variable "google_oauth_client_secret" {
  type      = string
  default   = ""
  nullable  = false
  sensitive = true
}

variable "callback_urls" {
  description = "OAuth 로그인 성공 후 돌아올 프론트엔드 URL 목록"
  type        = list(string)
  default     = []
}

variable "logout_urls" {
  description = "로그아웃 후 돌아올 프론트엔드 URL 목록"
  type        = list(string)
  default     = []
}
