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

  # NAT Gateway는 idle이어도 시간당 과금이라 AZ별로 안 두고 전체 공용 1개로 절반 절감.
  # 트레이드오프: 그 NAT가 있는 AZ가 장애나면 다른 AZ의 프라이빗 서브넷도 잠깐 인터넷이 막힘 dd
  nat_gateway_count = 1
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

# 3. API [i] Gateway 모듈 호출 (VPC Link로 ALB와 연결, Cognito JWT로 인증)
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

  # backend/가 라우트별로 자체 인증(authenticate 미들웨어, Cognito GetUser 직접 검증)을
  # 이미 하고 있어서 - 여기서 POST 전체를 막으면 /auth/signup, /auth/login처럼
  # 원래 공개여야 할 라우트까지 막혀버림. 인가는 백엔드에 맡기고 게이트웨이는 그냥 통과.
  require_auth = false
}

# 4. 정적 웹 호스팅용 S3 버킷 (독립적, 다른 모듈과 의존관계 없음)
module "storage" {
  source = "./modules/storage"
  providers = { aws = aws.seoul,
    aws.us_east_1 = aws.us_east_1
  }
  route53_zone_name  = var.route53_zone_name
  region_name        = var.region_name
  route53_cloudfront = var.route53_cloudfront
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

# 5-4. 리뷰 사진/텍스트 동기 검열 Lambda (VPC 밖). review_pipeline(비동기)로 대체돼서 지금은
# backend가 더 이상 직접 invoke하지 않음 - 기존에 만들어진 리소스라 삭제하지 않고 그대로 둠
module "review_moderation" {
  source    = "./modules/review_moderation"
  providers = { aws = aws.seoul }

  region_name              = var.region_name
  review_photos_bucket_arn = module.storage.review_photos_bucket_arn
}

# 5-5. 리뷰 비동기 검열 파이프라인 (SQS -> EventBridge Pipe -> Step Functions -> worker Lambda).
# backend는 리뷰를 즉시 PENDING 상태로 저장하고 이 큐에 메시지만 보냄 - 검열 자체(Translate/
# Comprehend/Rekognition)는 worker가 비동기로 수행하고 결과를 DynamoDB/S3에 반영함
module "review_pipeline" {
  source    = "./modules/review_pipeline"
  providers = { aws = aws.seoul }

  region_name                  = var.region_name
  review_table_name            = module.dynamodb.product_reviews_table_name
  review_table_arn             = module.dynamodb.product_reviews_table_arn
  moderation_events_table_name = module.dynamodb.moderation_events_table_name
  moderation_events_table_arn  = module.dynamodb.moderation_events_table_arn
  quarantine_bucket_name       = module.storage.quarantine_bucket_name
  quarantine_bucket_arn        = module.storage.quarantine_bucket_arn
  public_review_bucket_name    = module.storage.review_photos_bucket_name
  public_review_bucket_arn     = module.storage.review_photos_bucket_arn
  public_review_bucket_domain  = module.storage.review_photos_bucket_regional_domain
}

# 5-6. 상품 카탈로그 변경 알림 (DynamoDB Streams -> EventBridge Pipe -> SNS -> 관리자 이메일 구독)
module "admin_notifications" {
  source    = "./modules/admin_notifications"
  providers = { aws = aws.seoul }

  region_name              = var.region_name
  product_table_stream_arn = module.dynamodb.product_catalog_table_stream_arn
  admin_email              = var.admin_notification_email
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

  # 번역 Lambda 호출 권한 (리뷰 검열은 이제 review_pipeline의 SQS 큐로 비동기 처리 - ECS가
  # review_moderation Lambda를 더 이상 직접 invoke하지 않음)
  lambda_invoke_arns = [module.translation.function_arn]

  # backend/(Express) 앱이 쓰는 리소스 연결
  user_pool_id                = module.cognito.user_pool_id
  user_pool_arn               = module.cognito.user_pool_arn
  user_pool_client_id         = module.cognito.app_client_id
  dynamodb_table_name         = module.dynamodb.user_profiles_table_name
  product_likes_table_name    = module.dynamodb.product_likes_table_name
  product_reviews_table_name  = module.dynamodb.product_reviews_table_name
  product_catalog_table_name  = module.dynamodb.product_catalog_table_name
  product_catalog_table_arn   = module.dynamodb.product_catalog_table_arn
  quarantine_bucket_name      = module.storage.quarantine_bucket_name
  quarantine_bucket_arn       = module.storage.quarantine_bucket_arn
  review_moderation_queue_url = module.review_pipeline.queue_url
  review_moderation_queue_arn = module.review_pipeline.queue_arn
  review_photos_bucket_name   = module.storage.review_photos_bucket_name
  review_photos_bucket_arn    = module.storage.review_photos_bucket_arn
  review_photos_bucket_domain = module.storage.review_photos_bucket_regional_domain
  bedrock_model_id            = var.bedrock_model_id
  tavily_api_key              = var.tavily_api_key

  # 관리자 페이지(routes/admin.js)가 쓰는 리소스
  moderation_events_table_name = module.dynamodb.moderation_events_table_name
  moderation_events_table_arn  = module.dynamodb.moderation_events_table_arn
  product_images_bucket_name   = module.storage.product_images_bucket_name
  product_images_bucket_arn    = module.storage.product_images_bucket_arn
  product_images_bucket_domain = module.storage.product_images_bucket_regional_domain

  # Amazon Managed Prometheus - 기본 꺼짐. 켜려면 AMP 워크스페이스를 콘솔에서 수동으로
  # 만들고 ARN을 tfvars(또는 CI 시크릿)로 넘겨야 함 (Remote Write URL은 compute 모듈이 자동 계산)
  enable_prometheus        = var.enable_prometheus
  prometheus_workspace_arn = var.prometheus_workspace_arn

  # 기타 변수
  region_name    = var.region_name
  aws_region     = var.aws_region
  container_port = var.container_port
}

# 6-1. EKS(Fargate) 모듈 - 기본 꺼짐(enable_eks). ECS를 대체하는 게 아니라 병행 구성 -
# 같은 backend 이미지(module.compute의 ECR)와 동일한 IAM 태스크 정책을 그대로 재사용해서
# 정책 JSON 중복 없이 필요할 때만 켜서 띄울 수 있게 함. us-east-1(DR)에는 만들지 않음 -
# 두 번째 재해복구 전략이 아니라 EKS 운영 경험을 보여주기 위한 시연용 병행 구성이기 때문
module "eks" {
  source    = "./modules/eks"
  providers = { aws = aws.seoul, kubernetes = kubernetes }

  enable_eks               = var.enable_eks
  eks_admin_principal_arns = var.eks_admin_principal_arns

  region_name        = var.region_name
  aws_region         = var.aws_region
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  container_port     = var.container_port

  # compute 모듈과 동일한 이미지/IAM 정책 재사용
  ecr_repository_url  = module.compute.ecr_repository_url
  ecs_task_policy_arn = module.compute.task_policy_arn

  # backend 앱 환경변수 - module.compute에 넘기는 것과 동일한 값 (Tavily 웹검색만 제외 -
  # k8s는 SSM SecureString 자동 주입이 없어서 이 병행 구성 범위 밖으로 둠)
  user_pool_id                 = module.cognito.user_pool_id
  user_pool_client_id          = module.cognito.app_client_id
  dynamodb_table_name          = module.dynamodb.user_profiles_table_name
  product_likes_table_name     = module.dynamodb.product_likes_table_name
  product_reviews_table_name   = module.dynamodb.product_reviews_table_name
  product_catalog_table_name   = module.dynamodb.product_catalog_table_name
  review_photos_bucket_name    = module.storage.review_photos_bucket_name
  review_photos_bucket_domain  = module.storage.review_photos_bucket_regional_domain
  bedrock_model_id             = var.bedrock_model_id
  quarantine_bucket_name       = module.storage.quarantine_bucket_name
  review_moderation_queue_url  = module.review_pipeline.queue_url
  moderation_events_table_name = module.dynamodb.moderation_events_table_name
  product_images_bucket_name   = module.storage.product_images_bucket_name
  product_images_bucket_domain = module.storage.product_images_bucket_regional_domain
}

# 7. AWS Managed Grafana - 기본 꺼짐(enable_grafana). CloudWatch(ECS/ALB)는 항상 보이고,
# Prometheus 패널은 AMP가 연결돼 있을 때만(prometheus_workspace_arn) 같이 붙음
module "grafana" {
  source    = "./modules/grafana"
  providers = { aws = aws.seoul }

  region_name = var.region_name
  aws_region  = var.aws_region

  enable_grafana              = var.enable_grafana
  grafana_admin_sso_group_ids = var.grafana_admin_sso_group_ids
  prometheus_workspace_arn    = var.prometheus_workspace_arn

  ecs_cluster_name = module.compute.cluster_name
  ecs_service_name = module.compute.service_name
  alb_arn_suffix   = module.alb.arn_suffix
}