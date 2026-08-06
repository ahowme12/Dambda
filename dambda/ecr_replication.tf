# 서울에 push된 백엔드 이미지를 us-east-1로 자동 복제 (계정/레지스트리 단위 설정이라
# 리전 하나에서만 선언하면 됨 - 소스는 특정 안 해도 되고, 목적지만 지정하면 그 목적지가
# 아닌 리전에 push된 이미지가 전부 대상이 됨). CI에서 두 리전에 각각 push할 필요 없이
# 서울에 한 번만 push하면 AWS가 알아서 us-east-1로 복사해줌.
data "aws_caller_identity" "root" {}

resource "aws_ecr_replication_configuration" "main" {
  provider = aws.seoul

  replication_configuration {
    rule {
      destination {
        region      = var.us_aws_region
        registry_id = data.aws_caller_identity.root.account_id
      }

      # my-app-dev-* 레포만 대상 - 계정에 다른 용도의 ECR 레포가 생겨도 자동으로 안 끌려오게 스코프
      repository_filter {
        filter      = "${var.region_name}-*"
        filter_type = "PREFIX_MATCH"
      }
    }
  }
}
