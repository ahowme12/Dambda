data "aws_caller_identity" "current" {}

data "aws_route53_zone" "primary" {
  count        = var.enable_cloudfront ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

# 정적 웹 호스팅용 S3 버킷 (버킷 이름 전역 유일성 확보를 위해 계정 ID 접미사 사용)
resource "aws_s3_bucket" "static_site" {
  bucket = "${var.region_name}-static-site-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-static-site" }
}

# enable_cloudfront=false인 호출부(DR 리전)용 - S3 website 호스팅 직접 공개.
# CloudFront를 쓰면 OAC가 버킷 접근을 전담하므로 이 리소스 자체가 불필요함
resource "aws_s3_bucket_website_configuration" "static_site" {
  count  = var.enable_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.static_site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

# CloudFront+OAC를 쓰면 버킷은 완전 비공개로 잠그고 CloudFront만 읽게 함.
# 안 쓰면(DR) 기존처럼 버킷을 직접 공개
resource "aws_s3_bucket_public_access_block" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  block_public_acls       = var.enable_cloudfront
  block_public_policy     = var.enable_cloudfront
  ignore_public_acls      = var.enable_cloudfront
  restrict_public_buckets = var.enable_cloudfront
}

# CloudFront가 S3를 프라이빗 오리진으로 읽기 위한 Origin Access Control (SigV4 서명)
resource "aws_cloudfront_origin_access_control" "static_site" {
  count                             = var.enable_cloudfront ? 1 : 0
  name                              = "${var.region_name}-static-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
# flutter_secure_storage(웹)의 토큰 저장이 브라우저 Web Crypto API를 쓰는데 이게
# secure context(HTTPS/localhost)에서만 동작함 - S3 website 호스팅은 HTTP만 지원해서
# 새로고침하면 로그인이 풀리는 원인이었음. CloudFront가 기본 *.cloudfront.net 인증서로
# 무료 HTTPS를 제공하므로 이 문제가 해결됨
resource "aws_cloudfront_distribution" "static_site" {
  count               = var.enable_cloudfront ? 1 : 0
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.route53_cloudfront]

  origin {
    domain_name              = aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id                = "s3-static-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_site[0].id
  }

  default_cache_behavior {
    target_origin_id       = "s3-static-site"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    # AWS 관리형 "CachingOptimized" 정책 - 별도 캐시 정책을 직접 정의할 필요 없음
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # Flutter 웹(SPA)은 클라이언트 사이드 라우팅이라 새로고침 시 존재하지 않는 경로로
  # 요청이 감 - index.html로 폴백시켜서 앱이 다시 뜨고 라우팅을 이어받게 함
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.acm[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = { Name = "${var.region_name}-static-site" }
}

# CloudFront(OAC) 전용 - 이 특정 배포에서 온 요청만 허용 (SourceArn 조건).
# 두 브랜치를 각각 jsonencode까지 끝낸 "문자열"로 만들어서 삼항연산자로 고르게 함 -
# HCL 객체 상태로 고르면 두 쪽의 속성 구성이 달라서(Condition 유무 등) 타입 통일이 안 됨
locals {
  static_site_bucket_policy_cloudfront_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOAC"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_site.arn}/*"
        Condition = {
          StringEquals = {
            # locals는 실제로 쓰이는지와 무관하게 항상 계산되므로, enable_cloudfront=false라
            # count=0인 storage_us에서도 이 표현식 자체는 평가됨 - one()으로 "0개면 null"
            # 처리해서 인덱스 에러를 피함 (이 local 자체는 storage_us에서 안 쓰이니 null이어도 무해)
            "AWS:SourceArn" = one(aws_cloudfront_distribution.static_site[*].arn)
          }
        }
      }
    ]
  })

  static_site_bucket_policy_public_json = jsonencode({
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
}

# CloudFront를 가리키는 Route 53 Alias 레코드 생성
resource "aws_route53_record" "cloudfront_alias" {
  count           = var.enable_cloudfront ? 1 : 0 # enable_cloudfront가 true일 때만 생성
  zone_id         = data.aws_route53_zone.primary[0].zone_id
  name            = var.route53_cloudfront # 서비스할 서브도메인
  allow_overwrite = true
  type            = "A"

  alias {
    name                   = aws_cloudfront_distribution.static_site[0].domain_name
    zone_id                = aws_cloudfront_distribution.static_site[0].hosted_zone_id # CloudFront는 항상 이 고정값(Z2FDTNDATAQYW2)을 사용합니다
    evaluate_target_health = false
  }
}
resource "aws_s3_bucket_policy" "static_site" {
  bucket = aws_s3_bucket.static_site.id

  policy = var.enable_cloudfront ? local.static_site_bucket_policy_cloudfront_json : local.static_site_bucket_policy_public_json

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

# 상품 카탈로그 이미지(정적, 시딩 스크립트로만 업로드). 원래 우리가 관리 안 하는 남의 계정
# 버킷(dambda-images.s3...)을 참조하고 있었는데 그쪽에 CORS가 없어서 Flutter 웹(CanvasKit)이
# 이미지를 못 받아왔음(모바일은 브라우저 CORS 제약이 없어서 멀쩡했음) - 우리 소유 버킷으로 옮김.
# review_photos와 같은 변수로 게이트: 이미지 URL이 절대경로라 서울 버킷 하나로 어느 리전
# 백엔드가 서빙하든 상관없어서 us-east-1엔 별도로 안 만듦(enable_review_photos_bucket=false)
resource "aws_s3_bucket" "product_images" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = "${var.region_name}-product-images-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-product-images" }
}

resource "aws_s3_bucket_public_access_block" "product_images" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.product_images[0].id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "product_images" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.product_images[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.product_images[0].arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.product_images]
}

resource "aws_s3_bucket_cors_configuration" "product_images" {
  count  = var.enable_review_photos_bucket ? 1 : 0
  bucket = aws_s3_bucket.product_images[0].id

  cors_rule {
    allowed_methods = ["GET"]
    allowed_origins = ["*"]
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# 모든 리뷰 사진이 처음 올라가는 곳(비공개, 항상 잠김) - review_pipeline의 worker Lambda가
# 검열을 통과시키면 review_photos로 옮기고 여기서는 지움
resource "aws_s3_bucket" "quarantine" {
  bucket = "${var.region_name}-quarantine-${data.aws_caller_identity.current.account_id}"

  tags = { Name = "${var.region_name}-quarantine" }
}

resource "aws_s3_bucket_public_access_block" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 검열이 실패/누락돼서 영원히 안 옮겨진 파일이 계속 쌓이는 걸 방지
resource "aws_s3_bucket_lifecycle_configuration" "quarantine" {
  bucket = aws_s3_bucket.quarantine.id

  rule {
    id     = "delete-quarantined-content-after-30-days"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}


# 1. us-east-1 리전에서 ACM 인증서 요청 (Wildcard 또는 서브도메인 지정)
resource "aws_acm_certificate" "acm" {
  provider          = aws.us_east_1 # CloudFront용이므로 반드시 us-east-1 리전 지정 필수!
  count             = var.enable_cloudfront ? 1 : 0
  domain_name       = var.route53_cloudfront # 실제 서비스할 도메인 주소
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# 2. ACM 인증서 DNS 검증을 위한 Route 53 레코드 자동 생성
resource "aws_route53_record" "acm_validation" {
  for_each = var.enable_cloudfront ? {
    for dvo in aws_acm_certificate.acm[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.primary[0].zone_id
}

# 3. DNS 검증 완료 대기 (테라폼이 검증될 때까지 기다렸다가 다음 단계로 진행)
resource "aws_acm_certificate_validation" "acm" {
  count    = var.enable_cloudfront ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.acm[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}