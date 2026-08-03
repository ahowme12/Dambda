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

output "table_arns" {
  description = "서울(홈 리전) ECS 태스크 IAM 정책에서 참조할 테이블/GSI ARN 목록"
  value = [
    aws_dynamodb_table.users.arn,
    aws_dynamodb_table.content.arn,
    "${aws_dynamodb_table.content.arn}/index/*",
    aws_dynamodb_table.translations.arn,
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
