variable "region_name" { type = string }
variable "product_table_stream_arn" { type = string }
variable "admin_email" {
  type    = string
  default = ""
}

# CloudWatch Alarm 대상 리소스 - 빈 문자열이면 해당 Alarm 자체를 안 만듦(grafana 모듈의
# ecs_cluster_name 패턴과 동일)
variable "ecs_cluster_name" {
  type    = string
  default = ""
}

variable "ecs_service_name" {
  type    = string
  default = ""
}

variable "alb_arn_suffix" {
  type    = string
  default = ""
}
