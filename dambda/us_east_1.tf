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
  source    = "./modules/storage"
  providers = { aws = aws.us_east_1 }

  region_name = var.us_region_name

  # backend 상품/리뷰 기능은 서울 단일 리전으로 유지 - 안 쓰는 리전에 공개 버킷 만들 이유 없음
  enable_review_photos_bucket = false

  # pilot light DR이라 실사용자가 없음 - CloudFront 배포 비용/시간 아낌
  enable_cloudfront = false
}

# 5. 컴퓨트 모듈 호출 (pilot light DR: 평소엔 태스크 0개로 콜드 대기)
module "compute_us" {
  source    = "./modules/compute"
  providers = { aws = aws.us_east_1 }

  vpc_id             = module.network_us.vpc_id
  private_subnet_ids = module.network_us.private_subnet_ids

  alb_security_group_id = module.alb_us.security_group_id
  target_group_arn      = module.alb_us.target_group_arn

  # DynamoDB 모듈에서 출력된 us-east-1 replica 테이블 ARN 연결
  dynamodb_table_arns = concat(
    module.dynamodb.replica_table_arns,
    module.dynamodb.replica_ported_table_arns,
  )

  # 번역 Lambda는 아직 서울에만 있음 - DR 전환 시 크로스 리전으로 호출 (지연 있음, 추후 리전별 배치 검토)
  lambda_invoke_arns = [module.translation.function_arn]

  # backend 상품/리뷰 기능은 서울 단일 리전으로 유지 - placeholder 컨테이너 그대로
  enable_backend_app = true

  # ECR 네이티브 리플리케이션은 같은 이름의 레포로만 복제되므로 서울과 동일한 이름을 그대로 씀
  # (region_name 접두어를 쓰면 my-app-dev-us-backend가 돼서 복제된 이미지가 안 보임)
  ecr_repository_name = "${var.region_name}-backend"

  # DynamoDB는 Global Table이라 테이블명이 리전 간 동일 - us-east-1 리전으로 만든 클라이언트가
  # 같은 이름으로 로컬 replica를 자동으로 찾아가므로 여기만 미리 배선해도 안전하게 동작함.
  # Cognito/S3(review_photos)/review_moderation Lambda는 서울 단일 리전 리소스라 백엔드 코드가
  # awsRegion(태스크 자신의 리전)으로 클라이언트를 만드는 한 크로스리전으로는 애초에 동작 안 해서
  # (리전 불일치로 항상 에러) 여기 안 넣음 - 넣어봐야 "설정된 것처럼 보이지만 항상 실패"만 됨
  dynamodb_table_name        = module.dynamodb.user_profiles_table_name
  product_likes_table_name   = module.dynamodb.product_likes_table_name
  product_reviews_table_name = module.dynamodb.product_reviews_table_name
  product_catalog_table_name = module.dynamodb.product_catalog_table_name
  product_catalog_table_arn  = module.dynamodb.replica_product_catalog_table_arn

  region_name    = var.us_region_name
  aws_region     = var.us_aws_region
  container_port = var.container_port

  # 재해 선언 시 이 세 값을 올려서(desired_count/min을 seoul과 동일하게) 수동 전환
  desired_count            = 0
  autoscaling_min_capacity = 0
  autoscaling_max_capacity = 5
}
