variable "region_name" {
  description = "리소스 이름 태그용 접두어"
  type        = string
}

variable "review_photos_bucket_arn" {
  description = "Rekognition이 S3Object 참조로 읽어들일 리뷰 사진 버킷 ARN (s3:GetObject 스코프용)"
  type        = string
}
