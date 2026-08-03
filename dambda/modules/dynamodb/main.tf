data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# 사용자 프로필 (Cognito sub = PK, 가입 시 선택한 locale 등 저장)
resource "aws_dynamodb_table" "users" {
  name         = "${var.region_name}-users"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "user_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  # Global Table 복제는 스트림을 통해 이루어지므로 필수
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-users" }
}

# 콘텐츠 (moderation_status는 업로드 즉시 노출 여부와 무관하게 관리자 검토 큐 용도)
resource "aws_dynamodb_table" "content" {
  name         = "${var.region_name}-content"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "content_id"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "moderation_status"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "N"
  }

  # 관리자 화면에서 "flagged/pending 최신순" 조회용
  global_secondary_index {
    name            = "moderation_status_index"
    projection_type = "ALL"

    key_schema {
      attribute_name = "moderation_status"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "created_at"
      key_type       = "RANGE"
    }
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-content" }
}

# 번역 캐시 (SK = "{content의 updated_at}#{locale}" 로 원본 수정 시 자동 캐시 무효화)
resource "aws_dynamodb_table" "translations" {
  name         = "${var.region_name}-translations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "content_id"
  range_key    = "version_locale"

  attribute {
    name = "content_id"
    type = "S"
  }

  attribute {
    name = "version_locale"
    type = "S"
  }

  # 옛 버전 캐시 항목은 조회되지 않을 뿐 자동 삭제되진 않으므로 TTL로 정리
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-translations" }
}
