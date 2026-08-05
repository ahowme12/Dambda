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

# ===================== 상품/리뷰 백엔드(backend/)용 테이블 =====================
# users(pk=user_id)를 재사용하지 않는 이유: backend 코드가 pk로 "userId"(카멜케이스)를
# 하드코딩하고 있어 키 속성명이 달라 스키마 자체가 안 맞음. 별도 테이블로 분리.

# 회원 프로필 (닉네임/국가 등, 비밀번호는 저장 안 함 - Cognito가 자격증명 전담)
resource "aws_dynamodb_table" "user_profiles" {
  name         = "${var.region_name}-user-profiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-user-profiles" }
}

# 상품 좋아요
resource "aws_dynamodb_table" "product_likes" {
  name         = "${var.region_name}-product-likes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "productId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "productId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-product-likes" }
}

# 상품 리뷰 (userId를 해시키로 둬서 "유저당 상품 1개 리뷰"를 PutItem ConditionExpression으로 강제)
resource "aws_dynamodb_table" "product_reviews" {
  name         = "${var.region_name}-product-reviews"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"
  range_key    = "productId"

  attribute {
    name = "userId"
    type = "S"
  }
  attribute {
    name = "productId"
    type = "S"
  }
  attribute {
    name = "createdAt"
    type = "S"
  }

  # "이 상품의 리뷰 최신순 목록" 조회용
  global_secondary_index {
    name            = "product-reviews-by-product"
    projection_type = "ALL"

    key_schema {
      attribute_name = "productId"
      key_type       = "HASH"
    }
    key_schema {
      attribute_name = "createdAt"
      key_type       = "RANGE"
    }
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-product-reviews" }
}

# 상품 카탈로그 (조회는 항상 전체 목록, 카테고리 필터는 클라이언트에서 처리)
resource "aws_dynamodb_table" "product_catalog" {
  name         = "${var.region_name}-product-catalog"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "itemId"

  attribute {
    name = "itemId"
    type = "S"
  }

  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  replica {
    region_name = var.replica_region
  }

  tags = { Name = "${var.region_name}-product-catalog" }
}
