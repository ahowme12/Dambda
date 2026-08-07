output "users_table_name" {
  value = aws_dynamodb_table.users.name
}

output "users_table_arn" {
  value = aws_dynamodb_table.users.arn
}

output "content_table_name" {
  value = aws_dynamodb_table.content.name
}

output "content_table_arn" {
  value = aws_dynamodb_table.content.arn
}

output "content_table_stream_arn" {
  description = "홈 리전(서울) Content 테이블 스트림 ARN - 검열 Lambda 트리거용"
  value       = aws_dynamodb_table.content.stream_arn
}

output "translations_table_name" {
  value = aws_dynamodb_table.translations.name
}

# ===================== backend/ (상품/리뷰) 용 테이블 출력 =====================

output "user_profiles_table_name" {
  value = aws_dynamodb_table.user_profiles.name
}

output "user_profiles_table_arn" {
  value = aws_dynamodb_table.user_profiles.arn
}

output "product_likes_table_name" {
  value = aws_dynamodb_table.product_likes.name
}

output "product_likes_table_arn" {
  value = aws_dynamodb_table.product_likes.arn
}

output "product_reviews_table_name" {
  value = aws_dynamodb_table.product_reviews.name
}

output "product_reviews_table_arn" {
  description = "GSI(product-reviews-by-product) 쿼리를 위해 base 테이블 ARN만으로는 부족 - IAM 정책에서 /index/* 추가 필요"
  value       = aws_dynamodb_table.product_reviews.arn
}

output "product_catalog_table_name" {
  value = aws_dynamodb_table.product_catalog.name
}

output "product_catalog_table_arn" {
  value = aws_dynamodb_table.product_catalog.arn
}

output "product_catalog_table_stream_arn" {
  description = "홈 리전(서울) product_catalog 스트림 ARN - admin_notifications 모듈(EventBridge Pipe)용"
  value       = aws_dynamodb_table.product_catalog.stream_arn
}

output "moderation_events_table_name" {
  value = aws_dynamodb_table.moderation_events.name
}

output "moderation_events_table_arn" {
  description = "GSI(status-detectedAt-index) 쿼리를 위해 base 테이블 ARN만으로는 부족 - IAM 정책에서 /index/* 추가 필요"
  value       = aws_dynamodb_table.moderation_events.arn
}

output "table_arns" {
  description = "서울(홈 리전) ECS 태스크 IAM 정책에서 참조할 테이블/GSI ARN 목록"
  value = [
    aws_dynamodb_table.users.arn,
    aws_dynamodb_table.content.arn,
    "${aws_dynamodb_table.content.arn}/index/*",
    aws_dynamodb_table.translations.arn,
    aws_dynamodb_table.moderation_events.arn,
    "${aws_dynamodb_table.moderation_events.arn}/index/*",
  ]
}

# Global Table의 replica는 aws_dynamodb_table 리소스가 ARN을 별도로 노출하지 않아서
# 계정ID/파티션/테이블명으로 직접 조립 (테이블명은 리전 간 동일해야 하는 Global Table 제약 이용)
output "replica_table_arns" {
  description = "us-east-1 replica 테이블/GSI ARN 목록 (compute_us의 IAM 정책에서 사용)"
  value = [
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.users.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.content.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.content.name}/index/*",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.translations.name}",
  ]
}

# backend/ 포팅 테이블(user_profiles/product_likes/product_reviews)의 us-east-1 replica ARN.
# product_catalog은 compute 모듈에서 별도 변수(product_catalog_table_arn)로 받아서 여기 안 섞음
output "replica_ported_table_arns" {
  description = "us-east-1 replica user_profiles/product_likes/product_reviews(+GSI) ARN 목록 (compute_us의 dynamodb_table_arns용)"
  value = [
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.user_profiles.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.product_likes.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.product_reviews.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.product_reviews.name}/index/*",
  ]
}

output "replica_product_catalog_table_arn" {
  description = "us-east-1 replica product_catalog 테이블 ARN (compute_us의 product_catalog_table_arn용)"
  value       = "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.product_catalog.name}"
}

output "replica_moderation_events_table_arn" {
  description = "us-east-1 replica moderation_events 테이블/GSI ARN 목록 (현재 review_pipeline은 서울 전용이라 아직 안 쓰이지만, 다른 테이블과 일관되게 노출)"
  value = [
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.moderation_events.name}",
    "arn:${data.aws_partition.current.partition}:dynamodb:${var.replica_region}:${data.aws_caller_identity.current.account_id}:table/${aws_dynamodb_table.moderation_events.name}/index/*",
  ]
}
