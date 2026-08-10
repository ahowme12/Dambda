variable "region_name" {
  type = string
}

variable "aws_region" {
  type = string
}

# AMG는 로그인에 AWS IAM Identity Center(SSO) 또는 SAML이 반드시 필요함 - 이 계정에
# Identity Center가 아직 활성화 안 돼 있으면(콘솔에서 한 번 켜야 함, Terraform으로 불가)
# 워크스페이스 자체는 만들어져도 아무도 로그인을 못 함
variable "enable_grafana" {
  description = "AWS Managed Grafana 워크스페이스 생성 여부. 켜기 전에 IAM Identity Center를 콘솔에서 먼저 활성화해야 함"
  type        = bool
  default     = false
}

# IAM Identity Center의 그룹 ID(콘솔의 Identity Center -> Groups에서 확인). 개별 사용자가
# 아니라 그룹으로 주는 이유: 관리자가 바뀌어도 Terraform 안 고치고 그룹 멤버만 관리하면 됨.
# 비어있으면 아무한테도 ADMIN 권한을 안 줘서, 워크스페이스는 생기지만 로그인해도 아무
# 권한이 없는 상태가 됨 - 워크스페이스 생성 이후 값을 채워서 재적용 필요
variable "grafana_admin_sso_group_ids" {
  description = "Grafana ADMIN 권한을 줄 IAM Identity Center 그룹 ID 목록"
  type        = list(string)
  default     = []
}

# Prometheus 데이터소스는 AMP 워크스페이스가 실제로 있어야 의미가 있음(콘솔에서 수동 생성,
# compute 모듈의 enable_prometheus와 동일 전제) - 비어있으면 CloudWatch 데이터소스만 구성됨
variable "prometheus_workspace_arn" {
  type    = string
  default = ""
}

variable "ecs_cluster_name" {
  description = "CloudWatch 대시보드 패널이 참조할 ECS 클러스터 이름"
  type        = string
  default     = ""
}

variable "ecs_service_name" {
  description = "CloudWatch 대시보드 패널이 참조할 ECS 서비스 이름"
  type        = string
  default     = ""
}

variable "alb_arn_suffix" {
  description = "CloudWatch 대시보드 패널이 참조할 ALB ARN suffix (예: app/my-app-dev-alb/abc123)"
  type        = string
  default     = ""
}
