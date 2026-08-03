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

  # DynamoDB 모듈에서 출력된 (홈 리전) 테이블 ARN 연결
  dynamodb_table_arns = module.dynamodb.table_arns

  # 번역 Lambda 호출 권한만 부여 (검열 Lambda는 ECS가 직접 호출하지 않음)
  lambda_invoke_arns = [module.translation.function_arn]

  # 기타 변수
  region_name    = var.region_name
  aws_region     = var.aws_region
  container_port = var.container_port
}