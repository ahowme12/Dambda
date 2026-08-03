variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "uploads_bucket_name" {
  description = "이미지 업로드 버킷 이름 (S3 이벤트 트리거 대상)"
  type        = string
}

variable "uploads_bucket_arn" {
  type = string
}

variable "content_table_name" {
  type = string
}

variable "content_table_arn" {
  type = string
}

variable "content_table_stream_arn" {
  description = "텍스트 콘텐츠 insert 감지용 DynamoDB Streams ARN"
  type        = string
}
