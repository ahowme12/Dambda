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

  # pilot light라 desired_count=0, 지금 이 리전에서 도는 태스크가 없어서 NAT 자체가 낭비.
  # DR 승격(desired_count 올릴 때) 같이 1 이상으로 올려야 함
  nat_gateway_count = 0
}

# 2. ALB 모듈 호출 (내부망 전용)
module "alb_us" {
  source    = "./modules/alb"
  providers = { aws = aws.us_east_1 }

  vpc_id             = module.network_us.vpc_id
  private_subnet_ids = module.network_us.private_subnet_ids
  region_name        = var.us_region_name
  container_port     = var.container_port

  vpc_link_security_group_id = module.api_gateway_us.vpc_link_security_group_id
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
  # backend 상품/리뷰 기능은 서울 단일 리전으로 유지 - 안 쓰는 리전에 공개 버킷 만들 이유 없음
  enable_review_photos_bucket = false

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

  # 번역 Lambda는 아직 서울에만 있음 - DR 전환 시 크로스 리전으로 호출 (지연 있음, 추후 리전별 배치 검토)
  lambda_invoke_arns = [module.translation.function_arn]

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
