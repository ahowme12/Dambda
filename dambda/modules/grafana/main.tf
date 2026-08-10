data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_iam_role" "grafana_workspace" {
  count = var.enable_grafana ? 1 : 0
  # -v2: terraform-provider-aws 버그(role_arn 값이 이전 apply와 같으면 UpdateWorkspace
  # 호출에 WorkspaceRoleArn을 아예 안 실어보냄) 때문에 SERVICE_MANAGED -> CUSTOMER_MANAGED로
  # 되돌리는 이번 apply에서 "When the permissionType is CUSTOMER_MANAGED a Workspace Role
  # ARN should be provided" 에러가 났음. role 이름을 바꿔서 role_arn 자체를 진짜로 바꾸면
  # provider가 변경을 감지해서 이번엔 제대로 AWS에 role_arn을 넘김
  name = "${var.region_name}-grafana-workspace-role-v2"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "grafana.amazonaws.com" }
    }]
  })
}

resource "aws_grafana_workspace" "main" {
  count = var.enable_grafana ? 1 : 0
  name  = "${var.region_name}-grafana-01"

  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  # SERVICE_MANAGED로 해봤더니 실제로 우려했던 대로(hashicorp/terraform-provider-aws#24342)
  # role_arn 역할에 CloudWatch/Prometheus 읽기 권한이 전혀 안 붙어서 대시보드가 전부 No data였음
  # (list-role-policies로 확인: attached/inline 정책 둘 다 0개). CUSTOMER_MANAGED로 되돌리고
  # 아래에서 직접 관리형 정책을 role에 붙여줌
  permission_type = "CUSTOMER_MANAGED"
  role_arn        = aws_iam_role.grafana_workspace[0].arn
  data_sources    = compact(["CLOUDWATCH", var.prometheus_workspace_arn != "" ? "PROMETHEUS" : ""])

  tags = { Name = "${var.region_name}-grafana" }
}

# CUSTOMER_MANAGED라 데이터소스 읽기 권한을 직접 붙여야 함 - AWS 관리형 정책 그대로 사용
resource "aws_iam_role_policy_attachment" "grafana_cloudwatch" {
  count = var.enable_grafana ? 1 : 0

  role       = aws_iam_role.grafana_workspace[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "grafana_prometheus" {
  count = var.enable_grafana && var.prometheus_workspace_arn != "" ? 1 : 0

  role       = aws_iam_role.grafana_workspace[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonPrometheusQueryAccess"
}

# 사용자 개별이 아니라 Identity Center 그룹 단위로 ADMIN을 줌 - 나중에 관리자가 바뀌어도
# Terraform 안 고치고 그룹 멤버만 추가/제거하면 됨. grafana_admin_sso_group_ids가
# 비어있으면(Identity Center를 아직 안 켰거나 그룹 ID를 아직 안 넣은 경우) 그냥 안 만듦 -
# 워크스페이스는 만들어지지만 아무도 로그인 후 권한이 없는 상태로 남게 됨
resource "aws_grafana_role_association" "admin" {
  count = var.enable_grafana && length(var.grafana_admin_sso_group_ids) > 0 ? 1 : 0

  role         = "ADMIN"
  group_ids    = var.grafana_admin_sso_group_ids
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
