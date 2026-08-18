# 기본 꺼짐 - 켜면 EKS 컨트롤플레인이 시간당 과금되기 시작하므로, ECS와 병행해서
# "필요할 때만" 띄우는 용도. 이 변수 하나가 이 모듈의 모든 리소스를 게이팅함
# (aws_grafana_workspace 모듈과 동일한 패턴 - 모듈은 항상 호출하고 내부에서 count로 게이팅)
variable "enable_eks" {
  description = "EKS(Fargate Profile) 클러스터 + backend 파드 배포 여부"
  type        = bool
  default     = false
}

variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "eks_cluster_version" {
  description = "EKS 클러스터 Kubernetes 버전"
  type        = string
  default     = "1.31"
}

variable "vpc_id" {
  description = "EKS 클러스터가 배치될 VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "EKS 클러스터 API 서버 ENI가 배치될 퍼블릭 서브넷 ID 리스트"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Fargate Profile(파드)이 배치될 프라이빗 서브넷 ID 리스트"
  type        = list(string)
}

variable "container_port" {
  description = "backend 컨테이너가 리스닝할 포트"
  type        = number
  default     = 80
}

# backend_foundation 모듈이 만든 것과 동일한 ECR 레포지토리/IAM 정책을 그대로 재사용 (정책
# JSON을 중복 작성하지 않기 위함 - modules/backend_foundation/outputs.tf)
variable "ecr_repository_url" {
  description = "재사용할 backend ECR 레포지토리 URL (backend_foundation 모듈 output)"
  type        = string
  default     = ""
}

variable "backend_task_policy_arn" {
  description = "재사용할 backend 태스크 IAM 정책 ARN - IRSA 롤에 그대로 attach함 (backend_foundation 모듈 output)"
  type        = string
  default     = ""
}

variable "backend_log_group_name" {
  description = "backend_foundation이 만든 CloudWatch 로그 그룹 이름 - aws-logging ConfigMap이 Fargate 로그를 여기로 라우팅함"
  type        = string
  default     = ""
}

# ALB 대상 그룹에 파드 IP를 직접 등록하기 위한 ARN(TargetGroupBinding) - 기존 API Gateway/
# Cognito 인증 체인을 그대로 재사용하기 위해 새 ELB를 안 만들고 이 대상 그룹을 그대로 씀
variable "alb_target_group_arn" {
  description = "기존 ALB 대상 그룹 ARN (modules/alb output)"
  type        = string
  default     = ""
}

# Amazon Managed Prometheus - 켜면 ADOT 사이드카 컨테이너가 파드에 추가됨(modules/compute와
# 동일한 조건)
variable "enable_prometheus" {
  description = "AMP로 애플리케이션 메트릭을 전송할지 여부 (ADOT 사이드카 컨테이너 추가됨)"
  type        = bool
  default     = false
}

variable "prometheus_remote_write_url" {
  description = "AMP Remote Write 엔드포인트 (workspace ARN에서 계산된 값 - 루트 main.tf에서 조립해 전달)"
  type        = string
  default     = ""
}

# ADOT 사이드카(enable_prometheus 전제)에 otlp receiver + awsxray exporter를 추가해서 X-Ray
# 분산 트레이싱을 받게 함. backend 컨테이너에도 ENABLE_TRACING env var로 전달됨
variable "enable_tracing" {
  description = "X-Ray 분산 트레이싱 활성화 여부 (enable_prometheus=true 필요)"
  type        = bool
  default     = false
}

# 값이 있으면 SSM SecureString을 읽어 k8s Secret으로 만들고 TAVILY_API_KEY로 주입함
variable "tavily_api_key_ssm_name" {
  description = "Tavily API 키가 저장된 SSM 파라미터 이름 (없으면 web_search 도구 자체를 안 줌)"
  type        = string
  default     = ""
}

# EKS API 인증 모드(access_config)에서 클러스터 관리 권한을 줄 IAM principal ARN 목록.
# CI 롤(github-actions-role, CI가 이 모듈을 apply할 때 필요)이나 로컬에서 직접 apply/kubectl할
# 본인의 IAM 사용자/역할 ARN을 여기에 넣어야 함 - 비워두면 아무도 클러스터에 접근 못 하는
# 상태로 생성됨(grafana_admin_sso_group_ids와 동일한 이유의 트레이드오프)
variable "eks_admin_principal_arns" {
  description = "EKS 클러스터 관리자 권한(AmazonEKSClusterAdminPolicy)을 줄 IAM principal ARN 목록"
  type        = list(string)
  default     = []
}

# ===================== backend/(Express) 앱 환경변수 =====================
# modules/compute와 동일한 변수 이름/의미 - 같은 이미지를 배포하므로 요구하는 값이 동일함.
# Tavily API 키(웹검색 tool-use)는 EKS 쪽엔 안 뚫음 - ECS는 SSM SecureString을 태스크
# 정의가 직접 주입해주지만, k8s는 그 결선(External Secrets Operator 등)이 따로 필요해서
# 이 병행 구성 범위에서는 뺌 (EKS면 이런 것도 별도로 관리해야 한다는 것 자체가 비교 포인트)
variable "user_pool_id" {
  type    = string
  default = ""
}

variable "user_pool_client_id" {
  type    = string
  default = ""
}

variable "dynamodb_table_name" {
  type    = string
  default = ""
}

variable "product_likes_table_name" {
  type    = string
  default = ""
}

variable "product_reviews_table_name" {
  type    = string
  default = ""
}

variable "product_catalog_table_name" {
  type    = string
  default = ""
}

variable "review_photos_bucket_name" {
  type    = string
  default = ""
}

variable "review_photos_bucket_domain" {
  type    = string
  default = ""
}

variable "bedrock_model_id" {
  type    = string
  default = ""
}

variable "bedrock_embedding_model_id" {
  type    = string
  default = ""
}

variable "quarantine_bucket_name" {
  type    = string
  default = ""
}

variable "review_moderation_queue_url" {
  type    = string
  default = ""
}

variable "moderation_events_table_name" {
  type    = string
  default = ""
}

variable "product_images_bucket_name" {
  type    = string
  default = ""
}

variable "product_images_bucket_domain" {
  type    = string
  default = ""
}
