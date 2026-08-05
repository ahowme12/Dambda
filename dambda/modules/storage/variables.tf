variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "enable_review_photos_bucket" {
  description = "리뷰 사진 버킷 생성 여부 (false면 아직 backend 기능을 확장 안 한 리전, 예: us-east-1 pilot light DR)"
  type        = bool
  default     = true
}

variable "enable_cloudfront" {
  description = "정적 사이트 앞에 CloudFront(HTTPS) 배치 여부 (false면 S3 직접 공개 + HTTP, DR 리전용)"
  type        = bool
  default     = true
}
