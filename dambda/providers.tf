# 멀티 리전 배포: 서울/미국 두 리전을 하나의 root에서 provider alias로 관리
# (VPC Peering, 향후 DynamoDB Global Table처럼 두 리전을 동시에 참조하는
#  리소스를 remote state 없이 같은 dependency 그래프 안에서 처리하기 위함)

provider "aws" {
  alias  = "seoul"
  region = var.aws_region

  # Cost Explorer/Budgets에서 태그 기준으로 이 프로젝트 지출만 걸러보기 위함 - provider
  # 단위로 설정하면 이 provider가 만드는 모든 리소스에 자동으로 붙어서, 리소스마다 개별로
  # tags를 안 챙겨도 됨(이미 있는 tags = {...}랑은 합쳐지지, 덮어쓰지 않음)
  default_tags {
    tags = {
      project = "dambda"
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = var.us_aws_region

  default_tags {
    tags = {
      project = "dambda"
    }
  }
}
