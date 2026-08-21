resource "aws_sns_topic" "product_changes" {
  name = "${var.region_name}-product-changes"
}

resource "aws_sns_topic_subscription" "admin_email" {
  count     = var.admin_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.product_changes.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

#######################################
# 운영 알림 (GuardDuty/Cost Anomaly/CloudWatch Alarm이 전부 여기로 모임) -
# product_changes와 별개 토픽으로 둬서 "상품 변경 알림"이랑 "운영 이상 알림"을 분리함.
# 나중에 이 토픽을 AWS Chatbot으로 Slack에 연결하면 알림 종류 상관없이 한 채널로 모임
#######################################

resource "aws_sns_topic" "ops_alerts" {
  name = "${var.region_name}-ops-alerts"
}

resource "aws_sns_topic_subscription" "ops_alerts_email" {
  count     = var.admin_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.ops_alerts.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

# GuardDuty Finding용 EventBridge 규칙(root main.tf)이 이 토픽에 Publish할 수 있어야 함 -
# SNS는 기본적으로 같은 계정 안에서도 서비스 프린시펄의 Publish를 자동 허용하지 않음
resource "aws_sns_topic_policy" "ops_alerts" {
  arn = aws_sns_topic.ops_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.ops_alerts.arn
      },
      {
        # Cost Anomaly Detection 구독(subscriber type=SNS)도 이 토픽에 Publish해야 함
        Sid       = "AllowCostAnomalyDetectionPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.ops_alerts.arn
      }
    ]
  })
}

#######################################
# CloudWatch Alarm - ECS/ALB 임계치 초과 시 위 SNS로 알림
#######################################

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  count               = var.ecs_cluster_name == "" ? 0 : 1
  alarm_name          = "${var.region_name}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS 서비스 CPU 사용률이 15분 연속 80% 초과"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  count               = var.ecs_cluster_name == "" ? 0 : 1
  alarm_name          = "${var.region_name}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS 서비스 메모리 사용률이 15분 연속 80% 초과"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  # var.alb_arn_suffix는 root main.tf에서 module.alb.arn_suffix를 항상 넘겨받아서 이 스택
  # 안에서는 실질적으로 절대 빈 문자열이 아님 - "빈 문자열이면 스킵" 형태의 count 조건은
  # 그 값이 아직 존재하지 않는 리소스(ALB)에서 나온 계산값이라 plan 시점에 알 수 없어서
  # "Invalid count argument"로 fresh 계정에서 apply 자체가 막히는 원인이었음. 실제로 옵션인
  # 적 없는 값이라 조건 제거(이 모듈을 ALB 없이 재사용할 일이 생기면 그때 진짜 toggle 변수로)
  count               = 1
  alarm_name          = "${var.region_name}-alb-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "ALB 뒤 타깃이 5xx를 5분 내 1건 이상 반환"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }
}

# alb_5xx는 백엔드가 이미 응답한 5xx만 봄 - 새 파드가 헬스체크에 계속 실패하는 중이면(예:
# 배포 직후 crash-loop) 5xx가 쌓이기 전에 먼저 이걸로 감지됨
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  count               = 1
  alarm_name          = "${var.region_name}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "ALB 타겟그룹에 헬스체크 실패한 대상이 있음"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  ok_actions          = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.alb_target_group_arn_suffix
  }
}

# alb_5xx는 백엔드가 응답한 뒤에야 잡히는 신호라 - VPC Link 연결 실패/JWT Authorizer 거부/
# throttling처럼 요청이 ALB까지 아예 도달하지 못하고 API Gateway 단계에서 끝나는 실패는
# 이 알람이 아니면 전혀 안 잡힘(Client -> API Gateway -> VPC Link -> ALB -> EKS 경로 중
# 가장 앞단)
resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  count               = 1
  alarm_name          = "${var.region_name}-api-gateway-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5xx"
  namespace           = "AWS/ApiGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "HTTP API Gateway가 5분 내 5xx를 5건 이상 반환"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiId = var.api_gateway_id
    Stage = "$default"
  }
}

# review_pipeline의 worker는 Translate/Comprehend/Rekognition을 순차 호출하는데, 외부 서비스
# throttling/에러가 나도 지금까지는 알림이 전혀 없어서 조용히 실패해도(DLQ로 넘어가도) 아무도
# 모르는 사각지대였음
resource "aws_cloudwatch_metric_alarm" "review_pipeline_worker_errors" {
  count               = 1
  alarm_name          = "${var.region_name}-review-pipeline-worker-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "리뷰 검열 파이프라인 worker Lambda가 에러를 반환함"
  alarm_actions       = [aws_sns_topic.ops_alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = var.review_pipeline_worker_function_name
  }
}


#######################################
# EventBridge Pipe IAM Role
#######################################

resource "aws_iam_role" "product_changes_pipe" {
  name = "${var.region_name}-product-changes-pipe-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "pipes.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


resource "aws_iam_role_policy" "product_changes_pipe" {
  name = "${var.region_name}-product-changes-pipe-policy"

  role = aws_iam_role.product_changes_pipe.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ]

        Resource = [
          var.product_table_stream_arn
        ]
      },

      {
        Effect = "Allow"

        Action = [
          "sns:Publish"
        ]

        Resource = aws_sns_topic.product_changes.arn
      }
    ]
  })
}


#######################################
# EventBridge Pipe
#######################################

resource "aws_pipes_pipe" "product_changes" {

  name = "${var.region_name}-product-changes-pipe"

  role_arn = aws_iam_role.product_changes_pipe.arn


  source = var.product_table_stream_arn

  target = aws_sns_topic.product_changes.arn


  source_parameters {

    dynamodb_stream_parameters {

      starting_position = "LATEST"

      batch_size = 10
    }


    # 상품 변경 이벤트만 전달
    filter_criteria {

      filter {

        pattern = jsonencode({

          eventName = [
            "INSERT",
            "MODIFY",
            "REMOVE"
          ]

        })
      }
    }
  }


  target_parameters {

    input_template = jsonencode({

      eventType = "<$.eventName>"

      productId = "<$.dynamodb.Keys.productId.S>"

      changedAt = "<aws.pipes.event.ingestion-time>"

    })
  }
}