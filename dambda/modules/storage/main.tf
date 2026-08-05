data "aws_caller_identity" "current" {}

# 정적 웹 호스팅용 S3 버킷 (버킷 이름 전역 유일성 확보를 위해 계정 ID 접미사 사용)
resource "aws_s3_bucket" "static_site" {
  bucket = "${var.region_name}-static-site-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-static-site" }
}

resource "aws_s3_bucket_website_configuration" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# 테스트용: CloudFront 없이 버킷을 직접 퍼블릭으로 열어둠 (추후 CloudFront+OAC로 교체 예정)
resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_site.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_site]
}

# 사용자 업로드(이미지 등) 저장용 - 정적 사이트 버킷과 분리된 프라이빗 버킷
resource "aws_s3_bucket" "uploads" {
  bucket = "${var.region_name}-uploads-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-uploads" }
}

resource "aws_s3_bucket_public_access_block" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 리뷰 사진 저장용 버킷. uploads(비공개)와 별개 - 리뷰 사진은 공개 조회가 필요해서
# 접근 정책이 정반대라 재사용 불가. 업로드(PutObject)는 ECS 태스크 IAM으로만 허용
# (버킷 정책이 아니라 IAM 정책 쪽, modules/compute 참고), 저장 전에 이미 검열 Lambda를 거침
resource "aws_s3_bucket" "review_photos" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = "${var.region_name}-review-photos-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-review-photos" }
}

resource "aws_s3_bucket_public_access_block" "review_photos" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.review_photos[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "review_photos" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.review_photos[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.review_photos[0].arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.review_photos]
}

# Flutter 웹(CanvasKit)은 이미지를 <img>가 아니라 fetch로 픽셀 데이터를 직접 받아오므로,
# 공개 읽기여도 CORS 헤더가 없으면 브라우저가 응답을 막음 - 테스트 단계라 전체 허용
resource "aws_s3_bucket_cors_configuration" "review_photos" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.review_photos[0].id

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# 배선 확인용 임시 테스트 페이지
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.static_site.id
  key          = "index.html"
  content_type = "text/html; charset=utf-8"
  content      = <<-EOT
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="UTF-8">
        <title>Static Site Test</title>
      </head>
      <body>
        <h1>S3 정적 웹 호스팅 테스트 페이지</h1>
        <p>이 페이지가 보이면 S3 정적 웹 호스팅 배선이 정상입니다.</p>
      </body>
    </html>
  EOT
}
