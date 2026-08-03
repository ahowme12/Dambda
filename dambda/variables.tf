# 기본 설정
variable "aws_region" {
  description = "AWS 리전 (예: ap-northeast-2)"
  type        = string
  default     = "ap-northeast-2"
}

variable "region_name" {
  description = "리소스 이름 태그용 식별자 (예: dev, prod)"
  type        = string
}

# 네트워크 설정
variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "퍼블릭 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "프라이빗 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

# 애플리케이션 설정
variable "container_port" {
  description = "컨테이너가 사용할 포트"
  type        = number
  default     = 80
}

variable "cors_allowed_origins" {
  description = "API Gateway CORS 허용 Origin 목록 (S3/CloudFront 프론트엔드 도메인 확정되면 * 대신 해당 도메인으로 좁힐 것)"
  type        = list(string)
  default     = ["*"]
}

# ===================== 미국(us-east-1) 리전 설정 =====================
# vpc_cidr는 서울과 겹치면 VPC Peering이 불가능하므로 반드시 다른 대역 사용

variable "us_aws_region" {
  description = "미국 리전"
  type        = string
  default     = "us-east-1"
}

variable "us_region_name" {
  description = "미국 리전 리소스 이름 태그용 식별자"
  type        = string
  default     = "my-app-dev-us"
}

variable "us_vpc_cidr" {
  description = "미국 리전 VPC CIDR 블록 (서울 10.0.0.0/16과 겹치지 않아야 함)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "us_public_subnets" {
  description = "미국 리전 퍼블릭 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "us_private_subnets" {
  description = "미국 리전 프라이빗 서브넷 CIDR 리스트"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.11.0/24"]
}