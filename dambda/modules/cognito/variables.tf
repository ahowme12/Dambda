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
