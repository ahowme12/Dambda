data "archive_file" "post_confirmation" {
  type        = "zip"
  source_dir  = "${path.module}/src/post_confirmation"
  output_path = "${path.module}/build/post_confirmation.zip"
}

resource "aws_iam_role" "post_confirmation_role" {
  name = "${var.region_name}-post-confirmation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "post_confirmation_logs" {
  role       = aws_iam_role.post_confirmation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "post_confirmation_dynamodb" {
  name = "${var.region_name}-post-confirmation-dynamodb"
  role = aws_iam_role.post_confirmation_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["dynamodb:PutItem"]
      Effect   = "Allow"
      Resource = var.dynamodb_users_table_arn
    }]
  })
}

resource "aws_lambda_function" "post_confirmation" {
  function_name    = "${var.region_name}-post-confirmation"
  role             = aws_iam_role.post_confirmation_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.post_confirmation.output_path
  source_code_hash = data.archive_file.post_confirmation.output_base64sha256

  environment {
    variables = {
      USERS_TABLE_NAME = var.dynamodb_users_table_name
    }
  }

  tags = { Name = "${var.region_name}-post-confirmation" }
}

resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.main.arn
}

resource "aws_cognito_user_pool" "main" {
  name = "${var.region_name}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # 가입폼에서 선택하는 언어 (앱/웹이 이 값 기준으로 번역된 콘텐츠를 보여줌)
  schema {
    name                = "locale"
    attribute_data_type = "String"
    mutable             = true
    required            = false

    string_attribute_constraints {
      min_length = 2
      max_length = 10
    }
  }

  lambda_config {
    post_confirmation = aws_lambda_function.post_confirmation.arn
  }

  tags = { Name = "${var.region_name}-user-pool" }
}

# 모바일 앱/웹 공용 퍼블릭 클라이언트
resource "aws_cognito_user_pool_client" "app" {
  name         = "${var.region_name}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    # backend/src/services/cognito.js가 로그인을 AdminInitiateAuth(ADMIN_USER_PASSWORD_AUTH)로
    # 처리함 - 이건 일반 USER_PASSWORD_AUTH와 별개로 앱 클라이언트에서 명시적으로 켜야 함
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
  ]
}

# 검열 큐 검토 등 관리자 전용 API 접근 판별용 그룹
resource "aws_cognito_user_group" "admin" {
  name         = "admin"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "콘텐츠 검열 큐 검토 권한을 가진 관리자 그룹"
}
