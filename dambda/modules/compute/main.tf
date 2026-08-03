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

# Lambda 및 AMP 사용을 위한 정책
resource "aws_iam_policy" "ecs_task_policy" {
  name = "${var.region_name}-ecs-task-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
    ]
  })
}

resource "aws_iam_role_policy_attachment" "task_permissions" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_task_policy.arn
}

# ECS 작업 정의 (사이드카 제거 및 App만 배치)
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.region_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name    = "app"
      image   = "node:20-alpine"
      command = ["node", "-e", "require('http').createServer((req,res)=>{res.writeHead(200,{'Content-Type':'text/html'});res.end('<h1>Hello from Node.js on Fargate</h1><p>path: '+req.url+'</p>')}).listen(${var.container_port})"]
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
    }
  ])
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