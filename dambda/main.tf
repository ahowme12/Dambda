# ===================== 서울 (ap-northeast-2) =====================

# 1. 네트워크 모듈 호출
module "network" {
  source    = "./modules/network"
  providers = { aws = aws.seoul }

  vpc_cidr        = var.vpc_cidr
  region_name     = var.region_name
  aws_region      = var.aws_region
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
}

# 2. ALB 모듈 호출 (compute의 의존성 해결, 내부망 전용)
module "alb" {
  source    = "./modules/alb"
  providers = { aws = aws.seoul }

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  region_name        = var.region_name
  container_port     = var.container_port

  # api_gateway 모듈의 VPC Link ENI에서 오는 트래픽만 허용
  vpc_link_security_group_id = module.api_gateway.vpc_link_security_group_id
}

# 3. API Gateway 모듈 호출 (VPC Link로 ALB와 연결, Cognito JWT로 인증)
module "api_gateway" {
  source    = "./modules/api_gateway"
  providers = { aws = aws.seoul }

  region_name        = var.region_name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # ALB 모듈에서 출력된 리스너로 프록시
  alb_listener_arn     = module.alb.listener_arn
  cors_allowed_origins = var.cors_allowed_origins

  # Cognito 모듈에서 출력된 User Pool로 JWT 검증
  cognito_issuer_url    = module.cognito.issuer_url
  cognito_app_client_id = module.cognito.app_client_id
}

# 4. 정적 웹 호스팅용 S3 버킷 (독립적, 다른 모듈과 의존관계 없음)
module "storage" {
  source    = "./modules/storage"
  providers = { aws = aws.seoul }

  region_name = var.region_name
}

# 5. DynamoDB 모듈 호출 (Global Table, 서울이 홈 리전 / us-east-1로 실시간 복제)
module "dynamodb" {
  source    = "./modules/dynamodb"
  providers = { aws = aws.seoul }

  region_name    = var.region_name
  replica_region = var.us_aws_region
}

# 5-1. Cognito 모듈 호출 (User Pool은 리전 간 자동 복제가 없어 서울 단일 리전만 소유)
module "cognito" {
  source    = "./modules/cognito"
  providers = { aws = aws.seoul }

  region_name = var.region_name
  aws_region  = var.aws_region

  dynamodb_users_table_name = module.dynamodb.users_table_name
  dynamodb_users_table_arn  = module.dynamodb.users_table_arn
}

# 5-2. 번역 Lambda (VPC 밖, ECS가 lambda:InvokeFunction으로 동기 호출)
module "translation" {
  source    = "./modules/translation"
  providers = { aws = aws.seoul }

  region_name = var.region_name
}

# 5-3. 검열 Lambda (VPC 밖, S3 업로드 이벤트 + Content 테이블 Streams로 트리거)
module "moderation" {
  source    = "./modules/moderation"
  providers = { aws = aws.seoul }

  region_name = var.region_name

  uploads_bucket_name = module.storage.uploads_bucket_name
  uploads_bucket_arn  = module.storage.uploads_bucket_arn

  content_table_name       = module.dynamodb.content_table_name
  content_table_arn        = module.dynamodb.content_table_arn
  content_table_stream_arn = module.dynamodb.content_table_stream_arn
}

# 5-4. 리뷰 사진/텍스트 동기 검열 Lambda (VPC 밖, backend가 리뷰 저장 전에 직접 invoke)
module "review_moderation" {
  source    = "./modules/review_moderation"
  providers = { aws = aws.seoul }

  region_name = var.region_name
}

# 6. 컴퓨트 모듈 호출
module "compute" {
  source    = "./modules/compute"
  providers = { aws = aws.seoul }

  # 네트워크 모듈에서 출력된 값 연결
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  # ALB 모듈에서 출력된 값 연결
  alb_security_group_id = module.alb.security_group_id
  target_group_arn      = module.alb.target_group_arn

  # DynamoDB 모듈에서 출력된 (홈 리전) 테이블 ARN 연결 - 기존 users/content/translations +
  # backend가 쓰는 user_profiles/product_likes/product_reviews(+GSI). product_catalog은
  # 읽기 전용이라 여기 안 섞고 compute 모듈에서 별도 변수로 받음
  dynamodb_table_arns = concat(
    module.dynamodb.table_arns,
    [
      module.dynamodb.user_profiles_table_arn,
      module.dynamodb.product_likes_table_arn,
      module.dynamodb.product_reviews_table_arn,
      "${module.dynamodb.product_reviews_table_arn}/index/*",
    ]
  )

  # 번역 Lambda + 리뷰 검열 Lambda 호출 권한 (검열 모듈의 비동기 moderate는 ECS가 직접 호출 안 함)
  lambda_invoke_arns = [module.translation.function_arn, module.review_moderation.function_arn]

  # backend/(Express) 앱이 쓰는 리소스 연결
  user_pool_id                  = module.cognito.user_pool_id
  user_pool_client_id           = module.cognito.app_client_id
  dynamodb_table_name           = module.dynamodb.user_profiles_table_name
  product_likes_table_name      = module.dynamodb.product_likes_table_name
  product_reviews_table_name    = module.dynamodb.product_reviews_table_name
  product_catalog_table_name    = module.dynamodb.product_catalog_table_name
  product_catalog_table_arn     = module.dynamodb.product_catalog_table_arn
  review_photos_bucket_name     = module.storage.review_photos_bucket_name
  review_photos_bucket_arn      = module.storage.review_photos_bucket_arn
  review_photos_bucket_domain   = module.storage.review_photos_bucket_regional_domain
  review_moderation_lambda_name = module.review_moderation.function_name

  # 기타 변수
  region_name    = var.region_name
  aws_region     = var.aws_region
  container_port = var.container_port
}