data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "grafana_workspace" {
  count = var.enable_grafana ? 1 : 0
  name  = "${var.region_name}-grafana-workspace-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
    }]
  })
}

locals {
  # CUSTOMER_MANAGED라 이 프로젝트의 다른 모든 모듈처럼 권한을 직접 정의함(AMG의
  # SERVICE_MANAGED 자동 생성 역할에 기대지 않음 - 프로젝트 전체의 명시적 IAM 원칙 유지)
  prometheus_statements = var.prometheus_workspace_arn != "" ? [
    {
      Action   = ["aps:QueryMetrics", "aps:GetLabels", "aps:GetSeries", "aps:GetMetricMetadata"]
      Effect   = "Allow"
      Resource = var.prometheus_workspace_arn
    },
    {
      # 워크스페이스 목록/설명 조회는 리소스 단위 스코프 미지원
      Action   = ["aps:ListWorkspaces", "aps:DescribeWorkspace"]
      Effect   = "Allow"
      Resource = "*"
    }
  ] : []
}

resource "aws_iam_role_policy" "grafana_workspace" {
  count = var.enable_grafana ? 1 : 0
  name  = "${var.region_name}-grafana-workspace-policy"
  role  = aws_iam_role.grafana_workspace[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          # Grafana CloudWatch 데이터소스 표준 읽기 권한 - 전부 리소스 단위 스코프 미지원
          Action = [
            "cloudwatch:DescribeAlarmsForMetric",
            "cloudwatch:DescribeAlarmHistory",
            "cloudwatch:DescribeAlarms",
            "cloudwatch:ListMetrics",
            "cloudwatch:GetMetricData",
            "cloudwatch:GetMetricStatistics",
            "ec2:DescribeTags",
            "ec2:DescribeInstances",
            "ec2:DescribeRegions",
            "tag:GetResources",
          ]
          Effect   = "Allow"
          Resource = "*"
        }
      ],
      local.prometheus_statements,
    )
  })
}

resource "aws_grafana_workspace" "main" {
  count = var.enable_grafana ? 1 : 0
  # 이전 실패한 시도(IAM 권한 누락)의 잔여 상태 때문인지 "my-app-dev-grafana" 이름으로
  # CreateWorkspace가 계속 409 ConflictException("Duplicate request for workspace")을
  # 반환해서 이름을 바꿔 회피함 - client_token은 매 apply마다 랜덤이라(provider 코드 확인함)
  # 그쪽 문제는 아니고, AWS 쪽에서 이름 단위로 뭔가 붙잡고 있는 것으로 보임
  name = "${var.region_name}-grafana-01"

  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana_workspace[0].arn
  data_sources             = compact(["CLOUDWATCH", var.prometheus_workspace_arn != "" ? "PROMETHEUS" : ""])

  tags = { Name = "${var.region_name}-grafana" }
}

# IAM Identity Center에서 만든 사용자에게 ADMIN을 줌 - grafana_admin_sso_user_ids가
# 비어있으면(Identity Center를 아직 안 켰거나 사용자 ID를 아직 안 넣은 경우) 그냥 안 만듦.
# 워크스페이스는 만들어지지만 아무도 로그인 후 권한이 없는 상태로 남게 됨
resource "aws_grafana_role_association" "admin" {
  count = var.enable_grafana && length(var.grafana_admin_sso_user_ids) > 0 ? 1 : 0

  role         = "ADMIN"
  user_ids     = var.grafana_admin_sso_user_ids
  workspace_id = aws_grafana_workspace.main[0].id
}

# Terraform이 grafana_data_source/grafana_dashboard를 만들 때 쓰는 API 인증 - 사람이 쓰는
# 계정이 아니라 자동화 전용 서비스 계정
resource "aws_grafana_workspace_service_account" "terraform" {
  count = var.enable_grafana ? 1 : 0

  name         = "terraform-automation"
  grafana_role = "ADMIN"
  workspace_id = aws_grafana_workspace.main[0].id
}

# 토큰은 수정이 안 되고(속성 바뀌면 재생성) 최대 30일까지만 유효함 - 그 이상 apply 없이
# 방치되면 만료되지만, 이건 Terraform이 대시보드를 자동으로 밀어넣는 용도로만 쓰이고
# Grafana 워크스페이스 사용 자체(사람이 로그인해서 보는 것)와는 무관해서 무해함
resource "aws_grafana_workspace_service_account_token" "terraform" {
  count = var.enable_grafana ? 1 : 0

  name               = "terraform-automation-token"
  service_account_id = aws_grafana_workspace_service_account.terraform[0].service_account_id
  seconds_to_live    = 2592000 # 30일(최대값)
  workspace_id       = aws_grafana_workspace.main[0].id
}
