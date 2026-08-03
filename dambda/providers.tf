# 멀티 리전 배포: 서울/미국 두 리전을 하나의 root에서 provider alias로 관리
# (VPC Peering, 향후 DynamoDB Global Table처럼 두 리전을 동시에 참조하는
#  리소스를 remote state 없이 같은 dependency 그래프 안에서 처리하기 위함)

provider "aws" {
  alias  = "seoul"
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = var.us_aws_region
}
