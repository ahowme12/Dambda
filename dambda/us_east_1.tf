# ===================== 미국 (us-east-1) =====================
# 서울 쪽과 동일한 modules/*를 재사용, provider만 aws.us_east_1로 지정

# 1. 네트워크 모듈 호출
module "network_us" {
  source    = "./modules/network"
  providers = { aws = aws.us_east_1 }

  vpc_cidr        = var.us_vpc_cidr
  region_name     = var.us_region_name
  aws_region      = var.us_aws_region
  public_subnets  = var.us_public_subnets
  private_subnets = var.us_private_subnets

  # pilot light라 기본 0 - Fargate 파드가 없으면 NAT 자체가 낭비. enable_eks_us=true로
  # DR 승격하면(module.eks_us 아래) 파드가 ECR pull/AWS API 호출에 인터넷 경로가 필요해서
  # 같이 1로 올라감
  nat_gateway_count = var.enable_eks_us ? 1 : 0

  # ECR/Logs Interface Endpoint도 NAT와 같은 이유로 게이팅 - 호출할 파드가 없으면 낭비
  enable_interface_endpoints = var.enable_eks_us
}

# 2. ALB 모듈 호출 (내부망 전용)
# TODO 비용 최적화 여지: EKS/Fargate가 없으면(enable_eks_us=false) 이 ALB도 타겟 0개인 빈
# 껍데기라 낭비지만, alb_us <-> api_gateway_us가 서로의 출력(vpc_link_security_group_id <->
# listener_arn)을 참조하는 구조라 둘 다에 count를 걸면 Terraform이 순환 참조로 잡아냄(실제
# apply 전 validate 단계에서 확인됨). 안전하게 끊으려면 ALB SG의 인바운드 규칙을 모듈
# 내부에서 var로 받는 대신 별도 aws_security_group_rule로 루트에서 연결하도록 리팩터링해야
# 하는데, 이건 서울 프로덕션이 쓰는 동일한 alb 모듈 계약을 바꾸는 일이라 실서비스 영향 검토
# 없이 손대지 않음. 그래서 이 둘은 일단 상시 생성 유지(월 ~$17.5, NAT/Interface Endpoint
# 대비 작은 비중)
module "alb_us" {
  source    = "./modules/alb"
  providers = { aws = aws.us_east_1 }

  vpc_id             = module.network_us.vpc_id
  private_subnet_ids = module.network_us.private_subnet_ids
  region_name        = var.us_region_name
  container_port     = var.container_port

  vpc_link_security_group_id = module.api_gateway_us.vpc_link_security_group_id

  # 뒤에 진짜 타겟이 없는(EKS 꺼진) pilot-light ALB라 방어할 트래픽 자체가 없음 - WAF 비용만 나감
  enable_waf = false
}

# 3. API Gateway 모듈 호출 (VPC Link로 ALB와 연결)
module "api_gateway_us" {
  source    = "./modules/api_gateway"
  providers = { aws = aws.us_east_1 }

  region_name        = var.us_region_name
  vpc_id             = module.network_us.vpc_id
  private_subnet_ids = module.network_us.private_subnet_ids

  alb_listener_arn     = module.alb_us.listener_arn
  cors_allowed_origins = var.cors_allowed_origins

  # Cognito User Pool은 리전 복제가 안 되므로 서울 Pool을 그대로 issuer로 재사용
  cognito_issuer_url    = module.cognito.issuer_url
  cognito_app_client_id = module.cognito.app_client_id

  # 서울과 동일 이유 - backend/가 라우트별 자체 인증을 하므로 게이트웨이 레벨 차단은 끔
  require_auth = false
}

# 4. 정적 웹 호스팅용 S3 버킷
module "storage_us" {
  source = "./modules/storage"
  providers = { aws = aws.us_east_1,
    aws.us_east_1 = aws.us_east_1
  }

  region_name = var.us_region_name

  route53_zone_name  = var.route53_zone_name
  route53_cloudfront = var.route53_cloudfront
  # backend 상품/리뷰 기능(컴퓨트) 자체는 서울 단일 리전으로 유지하지만, 버킷은 켜서
  # s3_replication.tf가 복제할 목적지로 씀 - EKS DR 승격 전까지는 아무도 안 쓰는 빈 버킷이라
  # 비용은 복제된 오브젝트 저장량뿐(리전 장애 시 이미지가 같이 날아가는 걸 막는 게 목적)
  enable_review_photos_bucket = true

  # pilot light DR이라 실사용자가 없음 - CloudFront 배포 비용/시간 아낌
  enable_cloudfront = false
}

# 5. backend 기반 리소스(ECR/IAM 정책/로그 그룹) - pilot light DR. EKS 컴퓨트를 이 리전에
# 아직 안 올려서(module.eks가 서울 전용) 실제로 트래픽을 받는 것은 없고, ECR 네이티브
# 리플리케이션 대상 + 향후 EKS DR을 붙일 때 쓸 로그 그룹/IAM 정책만 미리 갖춰둠
module "backend_foundation_us" {
  source    = "./modules/backend_foundation"
  providers = { aws = aws.us_east_1 }

  # DynamoDB 모듈에서 출력된 us-east-1 replica 테이블 ARN 연결
  dynamodb_table_arns = concat(
    module.dynamodb.replica_table_arns,
    module.dynamodb.replica_ported_table_arns,
  )


  # ECR 네이티브 리플리케이션은 같은 이름의 레포로만 복제되므로 서울과 동일한 이름을 그대로 씀
  # (region_name 접두어를 쓰면 my-app-dev-us-backend가 돼서 복제된 이미지가 안 보임)
  ecr_repository_name = "${var.region_name}-backend"

  product_catalog_table_arn = module.dynamodb.replica_product_catalog_table_arn

  region_name = var.us_region_name
  aws_region  = var.us_aws_region
}

# 6. GuardDuty - VPC/S3/IAM 사용 자체는 이 리전에도 있어서(트래픽이 0이어도) 서울과
# 동일하게 켬. Finding을 서울 SNS로 모으는 EventBridge 규칙은 안 만듦 - 크로스리전
# EventBridge 타깃팅은 별도 설정이 더 필요해서 범위 밖으로 둠(콘솔에서 이 리전 Finding도 확인 가능)
resource "aws_guardduty_detector" "us" {
  count    = var.enable_guardduty ? 1 : 0
  provider = aws.us_east_1
  enable   = true

  tags = { Name = "${var.us_region_name}-guardduty" }
}

# 7. EKS(Fargate) pilot-light DR - module.eks(main.tf, 서울)와 완전히 동일한 모듈을 그대로
# 재사용, provider와 리전별 리소스만 us-east-1 것으로 교체. enable_eks_us=false(기본값)면
# 이 모듈 안 count가 전부 0이라 아무 것도 안 생기고 비용도 0 - true로 바꾸면 서울과 동일한
# 스택(클러스터+Fargate+ALB Controller+ArgoCD까지)이 그대로 이 리전에도 뜸
module "eks_us" {
  source    = "./modules/eks"
  providers = { aws = aws.us_east_1, kubernetes = kubernetes.us_east_1, helm = helm.us_east_1 }

  enable_eks               = var.enable_eks_us
  eks_admin_principal_arns = var.eks_admin_principal_arns

  region_name        = var.us_region_name
  aws_region         = var.us_aws_region
  vpc_id             = module.network_us.vpc_id
  public_subnet_ids  = module.network_us.public_subnet_ids
  private_subnet_ids = module.network_us.private_subnet_ids
  container_port     = var.container_port

  ecr_repository_url      = module.backend_foundation_us.ecr_repository_url
  backend_task_policy_arn = module.backend_foundation_us.task_policy_arn
  backend_log_group_name  = module.backend_foundation_us.log_group_name

  alb_target_group_arn  = module.alb_us.target_group_arn
  alb_security_group_id = module.alb_us.security_group_id

  # DynamoDB는 Global Table이라 테이블 "이름"이 리전 무관하게 서울과 동일함(ARN만 리전별로
  # 다름) - 그래서 module.dynamodb의 서울 이름 output을 그대로 재사용. Cognito도 리전 복제가
  #안 되는 리소스라 서울 Pool을 그대로 씀(module.api_gateway_us가 이미 이렇게 재사용 중)
  user_pool_id                 = module.cognito.user_pool_id
  user_pool_client_id          = module.cognito.app_client_id
  dynamodb_table_name          = module.dynamodb.user_profiles_table_name
  product_likes_table_name     = module.dynamodb.product_likes_table_name
  product_reviews_table_name   = module.dynamodb.product_reviews_table_name
  product_catalog_table_name   = module.dynamodb.product_catalog_table_name
  moderation_events_table_name = module.dynamodb.moderation_events_table_name
  bedrock_model_id             = var.bedrock_model_id
  bedrock_embedding_model_id   = var.bedrock_embedding_model_id

  # 리뷰사진/상품이미지 버킷 자체는 이제 storage_us에 존재하고 s3_replication.tf로 서울에서
  # 계속 복제됨(리전 장애 시 이미지가 같이 날아가는 것 방지) - 다만 검열 큐(SQS)는 리전 복제가
  # 안 되는 리소스라 여전히 없고, pilot-light는 "컴퓨트 승격"이 목적이라 이 필드들은 빈 값으로
  # 둠 - DR 승격 시 이미지 업로드 기능까지 완전히 쓰려면 검열 파이프라인 자체를 이 리전에 별도로 세워야 함
  review_photos_bucket_name    = ""
  review_photos_bucket_domain  = ""
  quarantine_bucket_name       = ""
  review_moderation_queue_url  = ""
  product_images_bucket_name   = ""
  product_images_bucket_domain = ""

  tavily_api_key = var.tavily_api_key

  enable_prometheus           = var.enable_prometheus
  prometheus_remote_write_url = local.prometheus_remote_write_url
  enable_tracing              = var.enable_tracing
}
