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

# NAT Gateway는 트래픽과 무관하게 시간당 고정 과금이라(idle이어도 부과) 비용에 큰 비중을
# 차지함. null이면 기존처럼 AZ별 1개(고가용성 우선), 0이면 아예 안 만듦(아직 아무것도
# 안 도는 pilot light DR 리전용), 1이면 전체 AZ가 공유하는 NAT 1개만(비용/가용성 절충)
variable "nat_gateway_count" {
  description = "NAT Gateway 개수 (null=AZ별 1개, 0=없음, 1=전체 공용 1개)"
  type        = number
  default     = null
}