# backend 파드/컨테이너 로그 보관용 CloudWatch 로그 그룹. EKS Fargate는 ECS와 달리 로그가
# 자동으로 CloudWatch에 안 가서, kube-system의 aws-logging ConfigMap(modules/eks)이 이 그룹을
# 대상으로 Fluent Bit 라우팅을 명시적으로 구성해야 함
resource "aws_cloudwatch_log_group" "backend_logs" {
  name              = "/eks/${var.region_name}-logs"
  retention_in_days = 30
}

data "aws_caller_identity" "current" {}

# Tavily API 키 - EKS 파드는 컨테이너 시작 시 자동 주입 메커니즘이 없어서, modules/eks가
# 이 파라미터를 data source로 읽어 k8s Secret으로 옮겨 심음. 값이 없으면(로컬 개발 등)
# 리소스 자체를 안 만듦
resource "aws_ssm_parameter" "tavily_api_key" {
  count = var.tavily_api_key != "" ? 1 : 0
  name  = "/${var.region_name}/tavily-api-key"
  type  = "SecureString"
  value = var.tavily_api_key
}

# 백엔드 컨테이너 이미지 저장소. enable_backend_app이 false인 리전(아직 이 기능 범위 밖)에서는
# 만들지 않음
resource "aws_ecr_repository" "backend" {
  count                = var.enable_backend_app ? 1 : 0
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  count      = var.enable_backend_app ? 1 : 0
  repository = aws_ecr_repository.backend[0].name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "최근 10개 이미지만 보관"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# product_catalog은 읽기 전용(쓰기는 개발자가 시딩 스크립트로 직접), review_photos는 S3라
# 기존 dynamodb_table_arns/lambda_invoke_arns 배열과 액션 종류가 달라서 못 섞고 따로 분리.
# 값이 빈 문자열이면(이 기능을 안 쓰는 호출부) statement 자체를 빼야 함 - IAM 정책에
# Resource=""를 넣으면 apply 시점에 거부당하기 때문. (modules/compute에서 그대로 이전)
locals {
  product_catalog_statements = var.product_catalog_table_arn != "" ? [
    {
      Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
      Effect   = "Allow"
      Resource = var.product_catalog_table_arn
    }
  ] : []

  review_photos_statements = var.review_photos_bucket_arn != "" ? [
    {
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${var.review_photos_bucket_arn}/*"
    }
  ] : []

  # backend/src/services/cognito.js가 회원가입/로그인/내정보 조회에 Admin* API를 태스크
  # IAM 자격증명으로 직접 호출함. GetUser는 호출자의 액세스 토큰 기준으로 동작해 리소스
  # 단위 스코프를 지원 안 함 -> "*"
  cognito_statements = var.user_pool_arn != "" ? [
    {
      Action = [
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminSetUserPassword",
        "cognito-idp:AdminDeleteUser",
        "cognito-idp:AdminInitiateAuth",
        "cognito-idp:AdminListGroupsForUser",
      ]
      Effect   = "Allow"
      Resource = var.user_pool_arn
    },
    {
      Action   = ["cognito-idp:GetUser"]
      Effect   = "Allow"
      Resource = "*"
    }
  ] : []

  quarantine_statements = var.quarantine_bucket_arn != "" ? [
    {
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${var.quarantine_bucket_arn}/*"
    }
  ] : []

  review_queue_statements = var.review_moderation_queue_arn != "" ? [
    {
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = var.review_moderation_queue_arn
    }
  ] : []

  moderation_events_statements = var.moderation_events_table_arn != "" ? [
    {
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        # GET /notifications가 moderation-events-by-user GSI로 Query함 - GSI 조회는 테이블
        # ARN만으론 권한이 안 나서 /index/* 리소스가 따로 필요함
        "dynamodb:Query",
      ]
      Effect   = "Allow"
      Resource = [var.moderation_events_table_arn, "${var.moderation_events_table_arn}/index/*"]
    }
  ] : []

  product_images_statements = var.product_images_bucket_arn != "" ? [
    {
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${var.product_images_bucket_arn}/*"
    }
  ] : []

  # ADOT 사이드카(modules/eks)가 AMP로 메트릭을 remote-write함 - SigV4라 IAM 자격증명만
  # 있으면 됨. enable_prometheus=false면 이 권한 자체가 안 생김(최소 권한)
  prometheus_statements = var.enable_prometheus ? [
    {
      Action   = ["aps:RemoteWrite"]
      Effect   = "Allow"
      Resource = var.prometheus_workspace_arn
    }
  ] : []
}

# backend 런타임 IAM 정책 - IRSA 롤(modules/eks의 pod_irsa)이 그대로 attach함
resource "aws_iam_policy" "backend_task_policy" {
  name = "${var.region_name}-backend-task-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Action   = ["lambda:InvokeFunction"]
          Effect   = "Allow"
          Resource = var.lambda_invoke_arns
        },
        {
          # backend/src/services/bedrock.js(상품 Q&A) + embeddings.js(RAG) + translate.js(번역).
          # Foundation model이든 cross-region inference profile이든 리전별 ARN 형태가 달라서
          # 리소스 단위로 안 좁히고 "*"로 둠
          Action   = ["bedrock:InvokeModel"]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Query",
            "dynamodb:Scan",
          ]
          Effect   = "Allow"
          Resource = var.dynamodb_table_arns
        }
      ],
      local.product_catalog_statements,
      local.review_photos_statements,
      local.cognito_statements,
      local.quarantine_statements,
      local.review_queue_statements,
      local.moderation_events_statements,
      local.product_images_statements,
      local.prometheus_statements,
    )
  })
}
