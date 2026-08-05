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
}

# 4. 정적 웹 호스팅용 S3 버킷
module "storage_us" {
  source    = "./modules/storage"
  providers = { aws = aws.us_east_1 }

  region_name = var.us_region_name

  # backend 상품/리뷰 기능은 서울 단일 리전으로 유지 - 안 쓰는 리전에 공개 버킷 만들 이유 없음
  enable_review_photos_bucket = false
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
  dynamodb_table_arns = module.dynamodb.replica_table_arns

  # 번역 Lambda는 아직 서울에만 있음 - DR 전환 시 크로스 리전으로 호출 (지연 있음, 추후 리전별 배치 검토)
  lambda_invoke_arns = [module.translation.function_arn]

  # backend 상품/리뷰 기능은 서울 단일 리전으로 유지 - placeholder 컨테이너 그대로
  enable_backend_app = false

  region_name    = var.us_region_name
  aws_region     = var.us_aws_region
  container_port = var.container_port

  # 재해 선언 시 이 세 값을 올려서(desired_count/min을 seoul과 동일하게) 수동 전환
  desired_count            = 0
  autoscaling_min_capacity = 0
  autoscaling_max_capacity = 5
}
