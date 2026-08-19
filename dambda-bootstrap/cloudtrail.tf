# dambda(앱 인프라)가 아니라 여기(bootstrap)에 두는 이유: dambda는 통째로 destroy/재생성하는
# 주기가 있는데, CloudTrail은 "무슨 일이 있었는지"를 계속 추적하는 감사 도구라 그 사이클과
# 무관하게 계속 살아있어야 의미가 있음 - OIDC/IAM 롤/state 버킷과 같은 이유로 여기에 둠.
#
# 관리 이벤트(management events)만 켬(기본값, event_selector 안 씀) - S3 객체 단위/Lambda
# 호출 단위 같은 데이터 이벤트는 건당 과금이라 지금 목적(IAM Access Analyzer 정책 생성용
# 로그 확보)엔 불필요. 관리 이벤트 추적 자체는 계정당 무료 - 로그가 쌓이는 S3 스토리지
# 비용만 소액 발생함

resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${local.app_name_prefix}-cloudtrail-${local.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CloudTrail 서비스가 이 버킷에 로그를 쓸 수 있으려면 반드시 필요한 정책(AWS 공식 문서 그대로) -
# GetBucketAcl은 버킷 자체에, PutObject는 AWSLogs/<계정ID>/* 경로에만 (다른 계정 로그가
# 섞여 들어오는 걸 막는 bucket-owner-full-control 조건까지 AWS 권장 그대로 포함)
data "aws_iam_policy_document" "cloudtrail_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.cloudtrail.arn]
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket.json
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.app_name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  is_multi_region_trail         = true # ap-northeast-2 + us-east-1 둘 다 잡으려고
  include_global_service_events = true # IAM 같은 글로벌 서비스 이벤트도 포함
  enable_log_file_validation    = true # 로그 변조 탐지(무료)
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
