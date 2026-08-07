resource "aws_sns_topic" "product_changes" {
  name = "${var.region_name}-product-changes"
}

resource "aws_sns_topic_subscription" "admin_email" {
  count     = var.admin_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.product_changes.arn
  protocol  = "email"
  endpoint  = var.admin_email
}


########################################
# EventBridge Pipe IAM Role
########################################

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


########################################
# EventBridge Pipe
########################################

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