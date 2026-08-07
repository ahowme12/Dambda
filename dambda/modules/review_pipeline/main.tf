data "archive_file" "worker" {
  type        = "zip"
  source_dir  = "${path.module}/src/worker"
  output_path = "${path.module}/build/review-moderation-worker.zip"
}

resource "aws_sqs_queue" "dead_letter" {
  name                      = "${var.region_name}-review-moderation-dlq"
  message_retention_seconds = 1209600
}

resource "aws_sqs_queue" "review_moderation" {
  name                       = "${var.region_name}-review-moderation"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter.arn
    maxReceiveCount     = 5
  })
}

resource "aws_iam_role" "worker" {
  name = "${var.region_name}-review-moderation-worker-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_logs" {
  role       = aws_iam_role.worker.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "worker" {
  name = "${var.region_name}-review-moderation-worker-policy"
  role = aws_iam_role.worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # comprehend:DetectDominantLanguage는 translate:TranslateText가 SourceLanguageCode:'auto'일 때
      # 내부적으로 호출함(review_moderation Lambda와 동일 이유)
      { Effect = "Allow", Action = ["translate:TranslateText", "comprehend:DetectToxicContent", "comprehend:DetectDominantLanguage", "rekognition:DetectModerationLabels"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:DeleteObject"], Resource = "${var.quarantine_bucket_arn}/*" },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${var.public_review_bucket_arn}/*" },
      { Effect = "Allow", Action = ["dynamodb:UpdateItem"], Resource = var.review_table_arn },
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = var.moderation_events_table_arn }
    ]
  })
}

resource "aws_lambda_function" "worker" {
  function_name    = "${var.region_name}-review-moderation-worker"
  role             = aws_iam_role.worker.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  timeout          = 60
  filename         = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256

  environment {
    variables = {
      REVIEW_TABLE_NAME           = var.review_table_name
      MODERATION_EVENTS_TABLE     = var.moderation_events_table_name
      QUARANTINE_BUCKET           = var.quarantine_bucket_name
      PUBLIC_REVIEW_BUCKET        = var.public_review_bucket_name
      PUBLIC_REVIEW_BUCKET_DOMAIN = var.public_review_bucket_domain
      TOXICITY_THRESHOLD          = tostring(var.toxicity_threshold)
      IMAGE_CONFIDENCE_THRESHOLD  = tostring(var.image_confidence_threshold)
    }
  }
}

resource "aws_iam_role" "state_machine" {
  name = "${var.region_name}-review-moderation-state-machine-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "state_machine" {
  name = "${var.region_name}-review-moderation-state-machine-policy"
  role = aws_iam_role.state_machine.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["lambda:InvokeFunction"], Resource = aws_lambda_function.worker.arn }]
  })
}

resource "aws_sfn_state_machine" "review_moderation" {
  name     = "${var.region_name}-review-moderation"
  role_arn = aws_iam_role.state_machine.arn
  type     = "STANDARD"

  definition = jsonencode({
    Comment = "Processes one pending review supplied by the SQS moderation queue."
    StartAt = "Run moderation worker"
    States = {
      "Run moderation worker" = {
        Type       = "Task"
        Resource   = "arn:aws:states:::lambda:invoke"
        Parameters = { FunctionName = aws_lambda_function.worker.arn, "Payload.$" = "$" }
        Retry      = [{ ErrorEquals = ["Lambda.ServiceException", "Lambda.TooManyRequestsException", "States.Timeout"], IntervalSeconds = 2, MaxAttempts = 3, BackoffRate = 2.0 }]
        End        = true
      }
    }
  })
}

resource "aws_lambda_permission" "state_machine" {
  statement_id  = "AllowStepFunctionsInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.worker.function_name
  principal     = "states.amazonaws.com"
  source_arn    = aws_sfn_state_machine.review_moderation.arn
}

resource "aws_iam_role" "pipe" {
  name = "${var.region_name}-review-moderation-pipe-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "pipes.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "pipe" {
  name = "${var.region_name}-review-moderation-pipe-policy"
  role = aws_iam_role.pipe.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.review_moderation.arn },
      { Effect = "Allow", Action = ["states:StartExecution"], Resource = aws_sfn_state_machine.review_moderation.arn }
    ]
  })
}

resource "aws_pipes_pipe" "review_moderation" {
  name     = "${var.region_name}-review-moderation-pipe"
  role_arn = aws_iam_role.pipe.arn
  source   = aws_sqs_queue.review_moderation.arn
  target   = aws_sfn_state_machine.review_moderation.arn

  source_parameters {
    sqs_queue_parameters { batch_size = 1 }
  }

  target_parameters {
    step_function_state_machine_parameters { invocation_type = "FIRE_AND_FORGET" }
  }
}
