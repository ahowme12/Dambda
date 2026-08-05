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
          Action   = ["aps:RemoteWrite"]
          Effect   = "Allow"
          Resource = "*"
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
          Action = [
            "dynamodb:GetItem",
            "dynamodb:PutItem",
            "dynamodb:UpdateItem",
            "dynamodb:DeleteItem",
            "dynamodb:Query",
          ]
          Effect   = "Allow"
          Resource = var.dynamodb_table_arns
        }
      ],
      local.product_catalog_statements,
      local.review_photos_statements,
      local.cognito_statements,
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
  name                 = "${var.region_name}-backend"
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
      # 시크릿 없음 - Cognito가 자격증명을 전담하므로 클라이언트 시크릿/DB 비밀번호가 없음
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
        { name = "MODERATION_LAMBDA_NAME", value = var.review_moderation_lambda_name },
      ]
      } : {
      image       = "node:20-alpine"
      command     = ["node", "-e", "require('http').createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/html'});res.end('<h1>Hello from Node.js on Fargate</h1><p>path: '+req.url+'</p>')}).listen(${var.container_port})"]
      environment = []
    }
  )
}

resource "aws_ecs_task_definition" "main" {
  family                   = "${var.region_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([local.container_definition])
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