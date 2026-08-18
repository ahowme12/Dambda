terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.56.0"
    }
    # modules/grafana가 AMG 워크스페이스에 데이터소스/대시보드를 직접 밀어넣는 데 씀
    # (Grafana HTTP API를 감싼 별도 provider - AWS provider가 아님)
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.0"
    }
    # modules/eks가 클러스터 안에 Namespace/Deployment/Service를 직접 만드는 데 씀
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    # modules/eks가 AWS Load Balancer Controller/metrics-server를 helm 차트로 설치하는 데 씀.
    # kubernetes 커넥션 설정이 블록이 아니라 객체(kubernetes = {...})인 버전대가 필요해서 하한을 넉넉히 둠
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17, < 4.0"
    }
    # modules/eks의 IRSA OIDC Provider 등록에 필요한 TLS 인증서 지문 조회용
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}