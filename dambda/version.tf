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
  }
}