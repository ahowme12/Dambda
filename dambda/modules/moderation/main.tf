data "archive_file" "moderate" {
  type        = "zip"
  source_dir  = "${path.module}/src/moderate"
  output_path = "${path.module}/build/moderate.zip"
}

resource "aws_iam_role" "moderate_role" {
  name = "${var.region_name}-moderate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "moderate_logs" {
  role       = aws_iam_role.moderate_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "moderate_permissions" {
  name = "${var.region_name}-moderate-permissions"
  role = aws_iam_role.moderate_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Rekognition/Comprehend는 리소스 수준 권한 미지원이라 Resource "*"가 정상 형태
        Action   = ["rekognition:DetectModerationLabels"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["comprehend:DetectToxicContent"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${var.uploads_bucket_arn}/*"
      },
      {
        Action   = ["dynamodb:UpdateItem"]
        Effect   = "Allow"
        Resource = var.content_table_arn
      },
      {
        Action   = ["dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:DescribeStream"]
        Effect   = "Allow"
        Resource = var.content_table_stream_arn
      },
      {
        Action   = ["dynamodb:ListStreams"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "moderate" {
  function_name    = "${var.region_name}-moderate"
  role             = aws_iam_role.moderate_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.moderate.output_path
  source_code_hash = data.archive_file.moderate.output_base64sha256
  timeout          = 15

  environment {
    variables = {
      CONTENT_TABLE_NAME = var.content_table_name
    }
  }

  tags = { Name = "${var.region_name}-moderate" }
}

# 이미지 업로드 -> 검열 (S3 이벤트)
resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.moderate.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.uploads_bucket_arn
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = var.uploads_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.moderate.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

# 텍스트 콘텐츠 insert -> 검열 (DynamoDB Streams)
# MODIFY까지 잡으면 이 함수의 UpdateItem(moderation_status)이 다시 스트림을 발생시켜
# 무한 루프가 돌 수 있어서 INSERT만 필터링
resource "aws_lambda_event_source_mapping" "content_stream" {
  event_source_arn  = var.content_table_stream_arn
  function_name     = aws_lambda_function.moderate.arn
  starting_position = "LATEST"

  filter_criteria {
    filter {
      pattern = jsonencode({ eventName = ["INSERT"] })
    }
  }
}
