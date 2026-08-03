data "archive_file" "translate" {
  type        = "zip"
  source_dir  = "${path.module}/src/translate"
  output_path = "${path.module}/build/translate.zip"
}

resource "aws_iam_role" "translate_role" {
  name = "${var.region_name}-translate-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "translate_logs" {
  role       = aws_iam_role.translate_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "translate_permissions" {
  name = "${var.region_name}-translate-permissions"
  role = aws_iam_role.translate_role.id

  # Translate는 리소스 수준 권한을 지원하지 않아 Resource "*"가 정상 형태
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["translate:TranslateText"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "translate" {
  function_name    = "${var.region_name}-translate"
  role             = aws_iam_role.translate_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.translate.output_path
  source_code_hash = data.archive_file.translate.output_base64sha256
  timeout          = 10

  tags = { Name = "${var.region_name}-translate" }
}
