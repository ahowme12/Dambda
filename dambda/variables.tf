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