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

# 상품 Q&A(backend/src/services/bedrock.js)용. ap-northeast-2에서 Nova 온디맨드 직접 호출이
# 안 되면 apac 크로스리전 추론 프로파일 ID로 바꿔야 함 - Bedrock 콘솔의 Model access에서
# Nova 모델 액세스를 먼저 켜야 하고, 실제 사용 가능한 ID도 거기서 확인 필요
variable "bedrock_model_id" {
  description = "상품 Q&A에 쓸 Bedrock Nova 모델/추론 프로파일 ID"
  type        = string
  default     = "apac.amazon.nova-micro-v1:0"
}

# GitHub Actions 시크릿(TAVILY_API_KEY) -> TF_VAR_tavily_api_key로 주입됨 (terraform.yml 참고).
# 로컬 tfvars에는 절대 평문으로 안 넣음 - CI 환경변수로만 전달
variable "tavily_api_key" {
  description = "웹검색 tool-use용 Tavily API 키 (없으면 web_search 기능 비활성화)"
  type        = string
  default     = ""
  sensitive   = true
}

# GitHub Actions 시크릿(ADMIN_NOTIFICATION_EMAIL) -> TF_VAR_admin_notification_email로 주입됨
# (terraform.yml 참고). 값이 없으면 admin_notifications 모듈이 SNS 이메일 구독을 안 만듦
variable "admin_notification_email" {
  description = "상품 카탈로그 변경 알림(SNS)을 받을 관리자 이메일 주소"
  type        = string
  default     = ""
}

# 기본 꺼짐(false) - AMP는 Terraform으로 안 만들고(계정당 무료로 여러 개 만들 수 있는 리소스가
# 아니라 수동 생성 전제) 콘솔에서 워크스페이스를 직접 만든 뒤 ARN/Remote Write URL만 여기로 넘기면
# compute 모듈이 ADOT 사이드카를 붙여서 실제로 메트릭을 전송하기 시작함
variable "enable_prometheus" {
  description = "수동 생성한 AMP로 애플리케이션 메트릭을 전송할지 여부"
  type        = bool
  default     = false
}

variable "prometheus_workspace_arn" {
  description = "수동 생성한 Amazon Managed Prometheus Workspace ARN"
  type        = string
  default     = ""
}

variable "prometheus_remote_write_url" {
  description = "수동 생성한 AMP Workspace의 Remote Write URL"
  type        = string
  default     = ""
}

# 기본 꺼짐 - AWS Managed Grafana는 로그인에 IAM Identity Center(SSO)가 필요한데, 이건
# 계정에서 콘솔로 한 번 켜야 하는 선행 조건이라 Terraform으로 대신할 수 없음
variable "enable_grafana" {
  description = "AWS Managed Grafana 워크스페이스 생성 여부 (IAM Identity Center를 먼저 활성화해야 함)"
  type        = bool
  default     = false
}

# 워크스페이스를 먼저 만든 뒤 IAM Identity Center에서 그룹을 만들고 관리자를 그 그룹에
# 넣어야 실제로 로그인해서 ADMIN 권한을 쓸 수 있음 - 빈 배열이면 워크스페이스만 생기고
# 아무도 권한이 없는 상태로 남음(2단계 apply가 됨). 개별 사용자가 아니라 그룹으로 관리해서
# 나중에 관리자가 바뀌어도 Terraform을 다시 안 건드려도 됨
variable "grafana_admin_sso_group_ids" {
  description = "Grafana ADMIN 권한을 줄 IAM Identity Center 그룹 ID 목록"
  type        = list(string)
  default     = []
}

variable "route53_cloudfront" {
  description = "cloudfront에 연결할 대체 도메인 주소"
}

variable "route53_zone_name" {
  description = "route53의 zone name"
  type        = string
}