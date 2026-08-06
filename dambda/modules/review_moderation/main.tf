# backend/(ECS)가 리뷰 저장 전에 동기 호출(lambda:InvokeFunction)하는 요청/응답형 검열 함수.
# 기존 modules/moderation(비동기, S3 이벤트+DynamoDB Streams 트리거)과 트리거 방식이 완전히
# 달라서 별도 모듈로 분리함. 호출 권한(lambda:InvokeFunction)은 이 모듈이 아니라 호출하는 쪽인
# compute 모듈의 ECS 태스크 IAM 정책에서 부여함.

data "archive_file" "review_moderation" {
  type        = "zip"
  source_dir  = "${path.module}/src/review_moderation"
  output_path = "${path.module}/build/review_moderation.zip"
}

resource "aws_iam_role" "review_moderation_role" {
  name = "${var.region_name}-review-moderation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "review_moderation_logs" {
  role       = aws_iam_role.review_moderation_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "review_moderation_permissions" {
  name = "${var.region_name}-review-moderation-permissions"
  role = aws_iam_role.review_moderation_role.id

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
        # ap-northeast-2에서 DetectToxicContent가 지원 안 돼(NotAuthorizedException) 함수
        # 코드가 us-east-1로 직접 호출함 - IAM 정책은 리전 무관하게 동일 액션 허용이면 충분
        Action   = ["comprehend:DetectToxicContent"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # DetectToxicContent가 영어만 지원해서 Comprehend에 넣기 전에 Translate로 영어화함 -
        # Translate도 리소스 수준 권한 미지원이라 Resource "*"
        Action   = ["translate:TranslateText"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # Translate가 SourceLanguageCode: 'auto'일 때 내부적으로 Comprehend의
        # DetectDominantLanguage를 호출해서 언어를 판별함(DetectToxicContent와는 별개 액션) -
        # 이게 없으면 AccessDeniedException으로 번역 자체가 막힘. ap-northeast-2에서 정상 지원됨
        Action   = ["comprehend:DetectDominantLanguage"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        # DetectModerationLabels를 Image.S3Object로 호출하면 Rekognition이 호출자(이 Lambda
        # 역할)의 권한으로 S3를 읽음 - 서비스 자체 권한이 아니라서 이게 없으면 AccessDenied
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${var.review_photos_bucket_arn}/*"
      }
    ]
  })
}

resource "aws_lambda_function" "review_moderation" {
  function_name    = "${var.region_name}-review-moderation"
  role             = aws_iam_role.review_moderation_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.review_moderation.output_path
  source_code_hash = data.archive_file.review_moderation.output_base64sha256
  # Translate -> Comprehend가 순차 호출(체인)이라 15s는 빠듯함 - 여유를 둠
  timeout = 20

  tags = { Name = "${var.region_name}-review-moderation" }
}
