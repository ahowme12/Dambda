# 서울 리전 S3 버킷 3개(uploads/review_photos/product_images)를 us-east-1로 복제 -
# 전부 사용자가 올렸거나(uploads/review_photos) 우리가 소유해서 다시 구할 수 없는(product_images,
# 원래 남의 계정 버킷이었던 걸 옮겨온 것) 데이터라서 서울 리전 장애 시 통째로 사라지면 안 됨.
# static_site는 CI가 매 배포마다 다시 빌드/업로드하므로 제외, quarantine은 검열을 아직 안 거친
# (=문제 있을 수도 있는) 콘텐츠라 다른 리전까지 퍼뜨릴 이유가 없어서 제외(30일 뒤 자동 삭제되는
# 임시 버킷이기도 함).
#
# S3 복제는 버전관리(versioning)가 양쪽 버킷에 다 켜져 있어야 동작함 - 지금까지 이 버킷들은
# 버전관리가 꺼져 있었어서 먼저 켬. 그리고 복제는 "이 설정을 켠 이후의 새 쓰기"만 대상이라
# 이미 올라가 있던 기존 오브젝트(예: 상품 이미지 마이그레이션으로 이미 올린 파일들)는 자동으로
# 안 넘어감 - 필요하면 최초 1회 aws s3 sync로 수동 백필해야 함

locals {
  s3_replication_pairs = {
    uploads = {
      source_bucket = module.storage.uploads_bucket_name
      source_arn    = module.storage.uploads_bucket_arn
      dest_bucket   = module.storage_us.uploads_bucket_name
      dest_arn      = module.storage_us.uploads_bucket_arn
    }
    review_photos = {
      source_bucket = module.storage.review_photos_bucket_name
      source_arn    = module.storage.review_photos_bucket_arn
      dest_bucket   = module.storage_us.review_photos_bucket_name
      dest_arn      = module.storage_us.review_photos_bucket_arn
    }
    product_images = {
      source_bucket = module.storage.product_images_bucket_name
      source_arn    = module.storage.product_images_bucket_arn
      dest_bucket   = module.storage_us.product_images_bucket_name
      dest_arn      = module.storage_us.product_images_bucket_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "replication_source" {
  for_each = local.s3_replication_pairs
  provider = aws.seoul

  bucket = each.value.source_bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "replication_dest" {
  for_each = local.s3_replication_pairs
  provider = aws.us_east_1

  bucket = each.value.dest_bucket
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "s3_replication" {
  name = "${var.region_name}-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "s3.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "${var.region_name}-s3-replication-policy"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
        Resource = [for p in local.s3_replication_pairs : p.source_arn]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
        Resource = [for p in local.s3_replication_pairs : "${p.source_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
        Resource = [for p in local.s3_replication_pairs : "${p.dest_arn}/*"]
      },
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "main" {
  for_each = local.s3_replication_pairs
  provider = aws.seoul

  # 같은 버킷에 복제 규칙을 걸려면 버전관리가 먼저 켜져 있어야 함
  depends_on = [aws_s3_bucket_versioning.replication_source, aws_s3_bucket_versioning.replication_dest]

  bucket = each.value.source_bucket
  role   = aws_iam_role.s3_replication.arn

  rule {
    id     = "replicate-to-us-east-1"
    status = "Enabled"

    destination {
      bucket        = each.value.dest_arn
      storage_class = "STANDARD"
    }
  }
}
