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
  count               = var.alb_arn_suffix == "" ? 0 : 1
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