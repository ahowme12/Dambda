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
