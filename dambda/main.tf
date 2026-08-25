# ===================== 서울 (ap-northeast-2) =====================
# CI 트리거 확인용 (배포 워크플로우 동작 확인)

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

  google_oauth_client_id     = var.google_oauth_client_id
  google_oauth_client_secret = var.google_oauth_client_secret
  callback_urls              = ["https://${var.route53_cloudfront}/auth/callback"]
  logout_urls                = ["https://${var.route53_cloudfront}/login"]
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
# + 운영 알림(ALB Alarm, GuardDuty, Cost Anomaly Detection)도 같은 모듈의 ops_alerts 토픽으로 모음
module "admin_notifications" {
  source    = "./modules/admin_notifications"
  providers = { aws = aws.seoul }

  region_name              = var.region_name
  product_table_stream_arn = module.dynamodb.product_catalog_table_stream_arn
  admin_email              = var.admin_notification_email

  # EKS 파드 CPU/메모리는 CloudWatch(AWS/ECS 네임스페이스)로 안 잡혀서(HPA+Prometheus/Grafana가
  # 그 역할을 대신함) ecs_cluster_name/ecs_service_name은 더 이상 안 넘김 - admin_notifications
  # 모듈의 count 게이팅(ecs_cluster_name == "" ? 0 : 1)이 알아서 해당 알람들을 안 만듦
  alb_arn_suffix                       = module.alb.arn_suffix
  alb_target_group_arn_suffix          = module.alb.target_group_arn_suffix
  api_gateway_id                       = module.api_gateway.api_id
  review_pipeline_worker_function_name = module.review_pipeline.worker_function_name
}

# 5-7. GuardDuty - 계정/네트워크 이상행동 자동 탐지. Grafana/EKS와 달리 사전조건도 비용도
# 사실상 없어서(저트래픽 계정 기준) 다른 enable_*와 달리 기본 켜짐
resource "aws_guardduty_detector" "main" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  tags = { Name = "${var.region_name}-guardduty" }
}

# GuardDuty Finding -> EventBridge -> ops_alerts SNS. GuardDuty 자체엔 SNS 구독 개념이 없어서
# (Cost Anomaly Detection과 다름) EventBridge 규칙으로 Finding 이벤트를 가로채야 함
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.region_name}-guardduty-findings"
  description = "GuardDuty Finding 발생 시 ops_alerts SNS로 전달"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "ops-alerts-sns"
  arn       = module.admin_notifications.ops_alerts_topic_arn
}

# 5-8. Cost Anomaly Detection - 완전 무료, 평소 지출 패턴 대비 이상 급증을 자동 알림.
# Cost Explorer API는 리전과 무관하게 us-east-1 엔드포인트로만 호출 가능해서 us_east_1
# provider를 쓰지만, DR과는 무관한 계정 전체(글로벌) 개념의 리소스임.
# AWS는 Cost Explorer가 켜진 계정마다 DIMENSIONAL/SERVICE 타입 모니터를 "Default-Services-Monitor"
# 라는 고정된 이름으로 자동 생성해두고, 이 dimension 타입은 계정당 1개로 제한함 - 그래서 별도
# 이름으로 새로 만들면 "Limit exceeded on dimensional spend monitor creation"으로 실패함.
# 새로 만드는 대신 그 기본 모니터를 이 리소스 주소로 import해서 그대로 재사용함(테라폼 import).
resource "aws_ce_anomaly_monitor" "main" {
  count             = var.enable_cost_anomaly_detection ? 1 : 0
  provider          = aws.us_east_1
  name              = "Default-Services-Monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "main" {
  count    = var.enable_cost_anomaly_detection ? 1 : 0
  provider = aws.us_east_1
  name     = "${var.region_name}-cost-anomaly-subscription"
  # DAILY/WEEKLY 다이제스트는 Email 구독자만 지원함(AWS 제약) - SNS(->Slack) 구독은
  # IMMEDIATE만 가능. 어차피 SNS->Chatbot 파이프라인 자체가 실시간 알림 목적이라 더 적합함
  frequency = "IMMEDIATE"

  monitor_arn_list = [aws_ce_anomaly_monitor.main[0].arn]

  subscriber {
    type    = "SNS"
    address = module.admin_notifications.ops_alerts_topic_arn
  }

  # 이상탐지 1건당 임팩트(달러)가 이 값 이상일 때만 알림 - 전체 월 예상 지출(~$150~190) 대비
  # 너무 작은 변동까지 매일 알림 오면 소음이 되므로 $10 이상만 걸러서 통지
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["10"]
    }
  }
}

# 5-9. Slack 알림(AWS Chatbot) - 기본 꺼짐. AWS Console에서 Slack 워크스페이스를 먼저
# 1회 수동으로 인증해야(Chatbot 콘솔 -> Configure new client -> Slack) slack_team_id가
# 발급됨 - Terraform으로 이 최초 인증 자체는 대신할 수 없음(Slack OAuth라 AWS API 밖의 절차).
# 인증 후 그 값 + 채널 ID를 tfvars로 넘기면 ops_alerts/product_changes 두 토픽이 같은
# Slack 채널로 연결됨 - GuardDuty/Cost Anomaly/CloudWatch Alarm/상품변경 알림이 전부 한 곳에 모임
resource "aws_iam_role" "chatbot" {
  count = var.enable_slack_alerts ? 1 : 0
  name  = "${var.region_name}-chatbot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "chatbot.amazonaws.com" }
    }]
  })
}

# 알림 자체는 SNS 구독으로 전달됨 - 이 권한은 Chatbot이 관련 리소스 상세를 조회해서 Slack
# 메시지를 더 읽기 좋게 만들 때 씀(AWS 공식 가이드가 권장하는 최소 세트)
resource "aws_iam_role_policy" "chatbot" {
  count = var.enable_slack_alerts ? 1 : 0
  name  = "${var.region_name}-chatbot-policy"
  role  = aws_iam_role.chatbot[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["cloudwatch:Describe*", "cloudwatch:Get*", "cloudwatch:List*"]
      Resource = "*"
    }]
  })
}

resource "aws_chatbot_slack_channel_configuration" "ops" {
  count              = var.enable_slack_alerts ? 1 : 0
  configuration_name = "${var.region_name}-ops-alerts"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack_team_id
  slack_channel_id   = var.slack_channel_id

  sns_topic_arns = [
    module.admin_notifications.ops_alerts_topic_arn,
    module.admin_notifications.topic_arn,
  ]

  tags = { Name = "${var.region_name}-chatbot" }
}

# 6. backend 기반 리소스(ECR/IAM 정책/로그 그룹) - ECS를 걷어내면서 EKS와 무관하게 계속
# 필요한 부분만 별도 모듈로 분리(구 modules/compute)
module "backend_foundation" {
  source    = "./modules/backend_foundation"
  providers = { aws = aws.seoul }

  # DynamoDB 모듈에서 출력된 (홈 리전) 테이블 ARN 연결 - 기존 users/content/translations +
  # backend가 쓰는 user_profiles/product_likes/product_reviews(+GSI). product_catalog은
  # 읽기 전용이라 여기 안 섞고 별도 변수로 받음
  dynamodb_table_arns = concat(
    module.dynamodb.table_arns,
    [
      module.dynamodb.user_profiles_table_arn,
      module.dynamodb.product_likes_table_arn,
      module.dynamodb.product_reviews_table_arn,
      "${module.dynamodb.product_reviews_table_arn}/index/*",
    ]
  )


  user_pool_arn               = module.cognito.user_pool_arn
  product_catalog_table_arn   = module.dynamodb.product_catalog_table_arn
  quarantine_bucket_arn       = module.storage.quarantine_bucket_arn
  review_moderation_queue_arn = module.review_pipeline.queue_arn
  review_photos_bucket_arn    = module.storage.review_photos_bucket_arn
  moderation_events_table_arn = module.dynamodb.moderation_events_table_arn
  product_images_bucket_arn   = module.storage.product_images_bucket_arn

  # Amazon Managed Prometheus - 기본 꺼짐. 켜려면 AMP 워크스페이스를 콘솔에서 수동으로
  # 만들고 ARN을 tfvars(또는 CI 시크릿)로 넘겨야 함
  enable_prometheus        = var.enable_prometheus
  prometheus_workspace_arn = var.prometheus_workspace_arn
  tavily_api_key           = var.tavily_api_key

  region_name = var.region_name
  aws_region  = var.aws_region
}

# AMP Remote Write 엔드포인트 - workspace ARN에서 워크스페이스 ID만 뽑아 조립(grafana 모듈의
# Prometheus datasource URL도 동일 패턴)
locals {
  prometheus_remote_write_url = var.prometheus_workspace_arn != "" ? "https://aps-workspaces.${var.aws_region}.amazonaws.com/workspaces/${element(split("/", var.prometheus_workspace_arn), 1)}/api/v1/remote_write" : ""
}

# 6-1. EKS(Fargate) 모듈 - backend를 실제로 서빙하는 컴퓨트. 기존 ALB 대상 그룹에 파드 IP를
# 직접 등록해서(TargetGroupBinding) API Gateway/Cognito 인증 체인을 그대로 재사용함.
# us-east-1(DR)에는 아직 만들지 않음 - DR 컴퓨트 승격 경로는 추후 별도 작업
module "eks" {
  source    = "./modules/eks"
  providers = { aws = aws.seoul, kubernetes = kubernetes, helm = helm }

  enable_eks               = var.enable_eks
  eks_admin_principal_arns = var.eks_admin_principal_arns

  region_name        = var.region_name
  aws_region         = var.aws_region
  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  container_port     = var.container_port

  # backend_foundation 모듈과 동일한 이미지/IAM 정책/로그 그룹 재사용
  ecr_repository_url      = module.backend_foundation.ecr_repository_url
  backend_task_policy_arn = module.backend_foundation.task_policy_arn
  backend_log_group_name  = module.backend_foundation.log_group_name

  # 기존 ALB 대상 그룹에 파드 IP를 직접 등록(TargetGroupBinding) - 새 ELB를 만들지 않음
  alb_target_group_arn  = module.alb.target_group_arn
  alb_security_group_id = module.alb.security_group_id

  # backend 앱 환경변수
  user_pool_id                 = module.cognito.user_pool_id
  user_pool_client_id          = module.cognito.app_client_id
  dynamodb_table_name          = module.dynamodb.user_profiles_table_name
  product_likes_table_name     = module.dynamodb.product_likes_table_name
  product_reviews_table_name   = module.dynamodb.product_reviews_table_name
  product_catalog_table_name   = module.dynamodb.product_catalog_table_name
  review_photos_bucket_name    = module.storage.review_photos_bucket_name
  review_photos_bucket_domain  = module.storage.review_photos_bucket_regional_domain
  bedrock_model_id             = var.bedrock_model_id
  bedrock_embedding_model_id   = var.bedrock_embedding_model_id
  quarantine_bucket_name       = module.storage.quarantine_bucket_name
  review_moderation_queue_url  = module.review_pipeline.queue_url
  moderation_events_table_name = module.dynamodb.moderation_events_table_name
  product_images_bucket_name   = module.storage.product_images_bucket_name
  product_images_bucket_domain = module.storage.product_images_bucket_regional_domain

  # backend_foundation이 SSM에 쓰는 것과 동일한 원본 값을 그대로 받음 - SSM에 썼다가 같은
  # apply 안에서 도로 읽는 방식은 리소스 생성 순서 문제(couldn't find resource)가 있어서 안  씀
  tavily_api_key = var.tavily_api_key

  enable_prometheus           = var.enable_prometheus
  prometheus_remote_write_url = local.prometheus_remote_write_url
  enable_tracing              = var.enable_tracing
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

  alb_arn_suffix                       = module.alb.arn_suffix
  waf_web_acl_name                     = module.alb.waf_web_acl_name
  api_gateway_id                       = module.api_gateway.api_id
  product_catalog_table_name           = module.dynamodb.product_catalog_table_name
  review_pipeline_worker_function_name = module.review_pipeline.worker_function_name
}