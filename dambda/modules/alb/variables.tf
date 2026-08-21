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

# internal ALB라도 API Gateway/VPC Link를 거쳐 들어온 요청을 WAF가 그대로 검사함 - 인터넷
# 노출 여부와 무관하게 동작함. DR(us-east-1)처럼 뒤에 진짜 타겟이 없는 ALB는 방어할 트래픽
# 자체가 없어서 비용만 나가므로 이 스위치로 끔(us_east_1.tf에서 false로 전달)
variable "enable_waf" {
  description = "이 ALB에 WAFv2 Web ACL을 붙일지 여부"
  type        = bool
  default     = true
}
