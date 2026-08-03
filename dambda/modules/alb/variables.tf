variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "vpc_id" {
  description = "ALB가 배치될 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "ALB가 배치될 프라이빗 서브넷 ID 리스트"
  type        = list(string)
}

variable "vpc_link_security_group_id" {
  description = "API Gateway VPC Link ENI가 사용하는 보안 그룹 ID (ALB 인바운드 허용 대상)"
  type        = string
}

variable "container_port" {
  description = "타겟 그룹이 전달할 컨테이너 포트"
  type        = number
  default     = 80
}
