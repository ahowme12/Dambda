variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
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