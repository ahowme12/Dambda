variable "vpc_cidr" {
  description = "VPC CIDR 블록"
  type        = string
}

variable "public_subnets" {
  description = "퍼블릭 서브넷 CIDR 리스트"
  type        = list(string)
}

variable "private_subnets" {
  description = "프라이빗 서브넷 CIDR 리스트"
  type        = list(string)
}

variable "region_name" {
  description = "리소스 이름 태그용 접두어 (ex: seoul, us-east)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "availability_zones" {
  description = "서브넷에 사용할 가용영역 접미사 리스트 (예: [\"a\", \"c\"])"
  type        = list(string)
  default     = ["a", "c"]
}