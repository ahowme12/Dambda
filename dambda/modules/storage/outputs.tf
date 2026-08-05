output "bucket_name" {
  description = "정적 웹 호스팅 S3 버킷 이름"
  value       = aws_s3_bucket.static_site.id
}

output "website_endpoint" {
  description = "S3 정적 웹 호스팅 엔드포인트 URL"
  value       = "http://${aws_s3_bucket_website_configuration.static_site.website_endpoint}"
}

output "uploads_bucket_name" {
  value = aws_s3_bucket.uploads.id
}

output "uploads_bucket_arn" {
  value = aws_s3_bucket.uploads.arn
}

# enable_review_photos_bucket=false인 호출부(storage_us)에서는 인덱스가 없어서 try()로 빈 문자열 처리
output "review_photos_bucket_name" {
  value = try(aws_s3_bucket.review_photos[0].id, "")
}

output "review_photos_bucket_arn" {
  value = try(aws_s3_bucket.review_photos[0].arn, "")
}

output "review_photos_bucket_regional_domain" {
  description = "리뷰 사진 공개 URL 조립에 쓰는 리전별 도메인 (backend의 S3_REVIEW_PHOTOS_DOMAIN)"
  value       = try(aws_s3_bucket.review_photos[0].bucket_regional_domain_name, "")
}
