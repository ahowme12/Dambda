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
