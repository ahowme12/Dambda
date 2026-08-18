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

# module.eks가 만드는(또는 enable_eks=false면 안 만드는) 클러스터 정보를 조회해서 kubernetes
# provider를 구성함. enable_eks=false일 때도 이 데이터 소스/provider 블록 자체는 항상 평가되지만
# module.eks.cluster_name이 빈 문자열이라 조회가 비어서 try()로 감싼 값들이 전부 ""가 되고,
# 이 provider를 쓰는 kubernetes_* 리소스도 전부 count=0이라 실제로 호출되지는 않음
# (클러스터+워크로드를 한 번의 apply로 같이 다루는 Terraform+EKS의 표준적인 우회 패턴)
data "aws_eks_cluster" "this" {
  count = var.enable_eks ? 1 : 0
  name  = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  count = var.enable_eks ? 1 : 0
  name  = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = try(data.aws_eks_cluster.this[0].endpoint, "")
  cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data), "")
  token                  = try(data.aws_eks_cluster_auth.this[0].token, "")
}

# AWS Load Balancer Controller/metrics-server 설치용 - kubernetes provider와 동일한 이유로
# enable_eks=false일 때도 try()로 감싸서 안전하게 빈 값으로 평가되게 함
provider "helm" {
  kubernetes = {
    host                   = try(data.aws_eks_cluster.this[0].endpoint, "")
    cluster_ca_certificate = try(base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data), "")
    token                  = try(data.aws_eks_cluster_auth.this[0].token, "")
  }
}
