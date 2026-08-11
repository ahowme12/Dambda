data "aws_caller_identity" "current" {}

# 로그 보관을 위한 CloudWatch 로그 그룹
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.region_name}-logs"
  retention_in_days = 30
}

# ECS 서비스를 담을 클러스터
resource "aws_ecs_cluster" "main" {
  name = "${var.region_name}-cluster"
}

# 컨테이너 접근 제어 보안 그룹 (ALB 트래픽 허용)
resource "aws_security_group" "ecs_sg" {
  name   = "${var.region_name}-ecs-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS 에이전트 실행 역할
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.region_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Tavily API 키(backend/src/services/websearch.js) - 평문 환경변수 대신 SSM SecureString에
# 저장하고 컨테이너 시작 시점에만 복호화되게 함. 값이 없으면(로컬 개발 등) 리소스 자체를 안 만듦
resource "aws_ssm_parameter" "tavily_api_key" {
  count = var.tavily_api_key != "" ? 1 : 0
  name  = "/${var.region_name}/tavily-api-key"
  type  = "SecureString"
  value = var.tavily_api_key
}

# ECS 실행 역할(태스크 역할이 아님)이 컨테이너 시작 시 SSM SecureString을 읽어서 주입함 -
# 기본 AWS 관리형 KMS 키(alias/aws/ssm)로 암호화되므로 그 키에 대한 Decrypt 권한도 같이 필요
resource "aws_iam_role_policy" "ecs_execution_ssm" {
  count = var.tavily_api_key != "" ? 1 : 0
  name  = "${var.region_name}-ecs-execution-ssm"
  role  = aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ssm:GetParameters"]
        Effect   = "Allow"
        Resource = [aws_ssm_parameter.tavily_api_key[0].arn]
      },
      {
        Action   = ["kms:Decrypt"]
        Effect   = "Allow"
        Resource = "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/aws/ssm"
      }
    ]
  })
}

# 앱 태스크 역할 (Lambda 호출 및 추후 AMP 권한 확보)
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.region_name}-ecs-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# product_catalog은 읽기 전용(쓰기는 개발자가 시딩 스크립트로 직접), review_photos는 S3라
# 기존 dynamodb_table_arns/lambda_invoke_arns 배열과 액션 종류가 달라서 못 섞고 따로 분리.
# 값이 빈 문자열이면(compute_us처럼 이 기능을 안 쓰는 호출부) statement 자체를 빼야 함 -
# IAM 정책에 Resource=""를 넣으면 apply 시점에 거부당하기 때문.
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
  # IAM 자격증명으로 직접 호출함 (API Gateway JWT authorizer가 아니라 백엔드 자체 인증).
  # GetUser는 호출자의 액세스 토큰 기준으로 동작해 리소스 단위 스코프를 지원 안 함 -> "*"
  cognito_statements = var.user_pool_arn != "" ? [
    {
      Action = [
        "cognito-idp:AdminCreateUser",
        "cognito-idp:AdminSetUserPassword",
        "cognito-idp:AdminDeleteUser",
        "cognito-idp:AdminInitiateAuth",
        # 관리자 페이지 접근 판별(services/cognito.js의 isAdmin)에 씀
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

  # backend가 리뷰 사진을 검열 전 임시로 올려두는 곳(review_pipeline의 worker가 승인 시 옮김)
  quarantine_statements = var.quarantine_bucket_arn != "" ? [
    {
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${var.quarantine_bucket_arn}/*"
    }
  ] : []

  # backend가 리뷰 저장 직후 비동기 검열 큐(review_pipeline)로 메시지를 보냄
  review_queue_statements = var.review_moderation_queue_arn != "" ? [
    {
      Action   = ["sqs:SendMessage"]
      Effect   = "Allow"
      Resource = var.review_moderation_queue_arn
    }
  ] : []

  # 관리자 페이지(routes/admin.js)가 검열 내역을 조회/수정/삭제함
  moderation_events_statements = var.moderation_events_table_arn != "" ? [
    {
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
      ]
      Effect   = "Allow"
      Resource = var.moderation_events_table_arn
    }
  ] : []

  # 관리자가 상품 등록/수정 시 올리는 이미지 (quarantine과 달리 검열 없이 바로 공개)
  product_images_statements = var.product_images_bucket_arn != "" ? [
    {
      Action   = ["s3:PutObject", "s3:DeleteObject"]
      Effect   = "Allow"
      Resource = "${var.product_images_bucket_arn}/*"
    }
  ] : []

  # ADOT 사이드카가 AMP로 메트릭을 remote-write함 - SigV4라 IAM 자격증명만 있으면 되고
  # 별도 API 키가 필요 없음. enable_prometheus=false면 이 권한 자체가 안 생김(최소 권한)
  prometheus_statements = var.enable_prometheus ? [
    {
      Action   = ["aps:RemoteWrite"]
      Effect   = "Allow"
      Resource = var.prometheus_workspace_arn
    }
  ] : []
}

# Lambda 및 AMP 사용을 위한 정책
resource "aws_iam_policy" "ecs_task_policy" {
  name = "${var.region_name}-ecs-task-policy"
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
          # backend/src/services/translate.js. Translate/Comprehend는 리소스 단위 스코프
          # 미지원이라 "*" 정상 형태. SourceLanguageCode:'auto' 쓰면 내부적으로
          # Comprehend 언어감지도 호출되므로 그 권한도 같이 필요함
          Action   = ["translate:TranslateText", "comprehend:DetectDominantLanguage"]
          Effect   = "Allow"
          Resource = "*"
        },
        {
          # backend/src/services/bedrock.js(상품 Q&A). Foundation model이든 cross-region
          # inference profile이든 리전별 ARN 형태가 달라서 리소스 단위로 안 좁히고 "*"로 둠
          # (translate/comprehend와 동일한 이유)
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
            # admin.js의 리뷰 관리 탭이 reviews.listAllReviews()에서 product_reviews를
            # 통째로 Scan함 (관리자 전용, 자주 호출 안 되니 Query로 못 바꾸는 것도 괜찮음)
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

resource "aws_iam_role_policy_attachment" "task_permissions" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# 백엔드 컨테이너 이미지 저장소 (로그인/회원가입/상품/리뷰 Express 앱). enable_backend_app이
# false인 호출부(compute_us)에서는 아직 만들지 않음 - 이미지를 아무도 push 안 하는 빈 리포지토리를
# 만들어봐야 의미 없고, "이 리전은 이 기능 범위 밖" 상태를 리소스 존재 여부로도 명확히 함.
resource "aws_ecr_repository" "backend" {
  count                = var.enable_backend_app ? 1 : 0
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
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

# ECS 작업 정의. enable_backend_app에 따라 실제 backend 이미지(ECR) 또는 배선 확인용
# placeholder(node:20-alpine 더미 서버) 중 하나로 컨테이너 정의를 조립함
locals {
  container_definition = merge(
    {
      name = "app"
      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    },
    var.enable_backend_app ? {
      image   = "${aws_ecr_repository.backend[0].repository_url}:latest"
      command = null
      environment = [
        { name = "PORT", value = tostring(var.container_port) },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "USER_POOL_ID", value = var.user_pool_id },
        { name = "USER_POOL_CLIENT_ID", value = var.user_pool_client_id },
        { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
        { name = "PRODUCT_LIKES_TABLE_NAME", value = var.product_likes_table_name },
        { name = "PRODUCT_REVIEWS_TABLE_NAME", value = var.product_reviews_table_name },
        { name = "PRODUCT_CATALOG_TABLE_NAME", value = var.product_catalog_table_name },
        { name = "S3_REVIEW_PHOTOS_BUCKET", value = var.review_photos_bucket_name },
        { name = "S3_REVIEW_PHOTOS_DOMAIN", value = var.review_photos_bucket_domain },
        { name = "BEDROCK_MODEL_ID", value = var.bedrock_model_id },
        { name = "QUARANTINE_BUCKET", value = var.quarantine_bucket_name },
        { name = "REVIEW_MODERATION_QUEUE_URL", value = var.review_moderation_queue_url },
        { name = "MODERATION_EVENTS_TABLE_NAME", value = var.moderation_events_table_name },
        { name = "S3_PRODUCT_IMAGES_BUCKET", value = var.product_images_bucket_name },
        { name = "S3_PRODUCT_IMAGES_DOMAIN", value = var.product_images_bucket_domain },
      ]
      # SSM SecureString - 평문 환경변수(environment)가 아니라 여기로 넣어야 task definition을
      # 조회해도 값이 노출되지 않고 컨테이너 시작 시점에만 실행 역할 권한으로 복호화됨
      secrets = var.tavily_api_key != "" ? [
        { name = "TAVILY_API_KEY", valueFrom = aws_ssm_parameter.tavily_api_key[0].arn }
      ] : []
      } : {
      image       = "node:20-alpine"
      command     = ["node", "-e", "require('http').createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/html'});res.end('<h1>Hello from Node.js on Fargate</h1><p>path: '+req.url+'</p>')}).listen(${var.container_port})"]
      environment = []
      secrets     = []
    }
  )

  # AMP Remote Write 엔드포인트는 workspace ARN에서 워크스페이스 ID만 뽑아 조립 가능해서
  # (grafana 모듈의 Prometheus datasource URL도 동일 패턴) 별도 변수로 안 받고 여기서 계산함 -
  # ARN 하나만 알면 되니 값 2개를 따로 맞춰줘야 하는 실수 여지가 없어짐
  prometheus_remote_write_url = var.prometheus_workspace_arn != "" ? "https://aps-workspaces.${var.aws_region}.amazonaws.com/workspaces/${element(split("/", var.prometheus_workspace_arn), 1)}/api/v1/remote_write" : ""

  # ADOT(AWS Distro for OpenTelemetry) 콜렉터가 같은 태스크 안에서 app 컨테이너의
  # 127.0.0.1:9090/metrics(backend/src/metrics.js)를 30초마다 긁어서 AMP로 SigV4 인증
  # remote-write함 - 같은 태스크 내부 통신이라 별도 서비스 디스커버리가 필요 없음
  adot_config = <<-YAML
    extensions:
      sigv4auth:
        region: ${var.aws_region}
        service: aps
    receivers:
      prometheus:
        config:
          scrape_configs:
            - job_name: dambda-backend
              scrape_interval: 30s
              static_configs:
                - targets: ["127.0.0.1:9090"]
    exporters:
      prometheusremotewrite:
        endpoint: ${local.prometheus_remote_write_url}
        auth:
          authenticator: sigv4auth
    service:
      extensions: [sigv4auth]
      # AMP로 실제 데이터가 하나도 안 들어오는데 기본 로그 레벨(info)에선 스크레이프/전송
      # 성공이든 실패든 아무것도 안 남아서 원인 파악이 안 됨 - 임시로 debug 로그를 켜서
      # 실제 HTTP 응답(4xx/5xx 등)을 확인하려는 용도. 원인 확인되면 다시 info로 낮출 것
      telemetry:
        logs:
          level: debug
      pipelines:
        metrics:
          receivers: [prometheus]
          exporters: [prometheusremotewrite]
  YAML

  adot_container_definition = {
    name              = "adot-collector"
    image             = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
    essential         = false
    memoryReservation = 128
    environment = [{
      name  = "AOT_CONFIG_CONTENT"
      value = local.adot_config
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "adot"
      }
    }
  }
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.region_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode(concat(
    [local.container_definition],
    var.enable_prometheus ? [local.adot_container_definition] : [],
  ))

  lifecycle {
    precondition {
      condition     = !var.enable_prometheus || var.prometheus_workspace_arn != ""
      error_message = "enable_prometheus=true이면 AMP Workspace ARN이 필요합니다."
    }
  }
}

# ECS 서비스
resource "aws_ecs_service" "main" {
  name            = "${var.region_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.container_port
  }
}

# 오토 스케일링 대상
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# CPU 기반 오토 스케일링 정책
resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "${var.region_name}-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 60.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}