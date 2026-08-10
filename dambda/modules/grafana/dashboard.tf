# Grafana HTTP API용 provider - AMG 워크스페이스가 있어야 값이 채워짐(enable_grafana=false면
# 전부 빈 문자열이 되는데, 그 경우 아래 grafana_* 리소스들도 count=0이라 provider가 실제로
# 쓰이질 않아서 무해함). 같은 모듈 안의 리소스로 provider를 구성하는 건 흔한 패턴(예: EKS
# 클러스터 attribute로 kubernetes provider 구성)이지만, provider가 먼저 존재해야 plan이
# 되는 특성상 최초 apply 한 번으로 워크스페이스+토큰+대시보드가 한 번에 안 끝나고
# 두 번째 apply에서 대시보드가 실제로 올라갈 수 있음 - 정상적인 동작이니 당황하지 않아도 됨
provider "grafana" {
  # enable_grafana=false여도 Terraform이 provider 설정 자체는 항상 검증해서, url/auth가
  # 빈 문자열이면(리소스가 하나도 없어도) "must not be empty" 에러로 plan이 통째로 실패함 -
  # 실제로 안 쓰이니(아래 리소스가 전부 count=0) 형식만 맞춘 placeholder를 넣어둠
  url  = try("https://${aws_grafana_workspace.main[0].endpoint}", "https://localhost")
  auth = try(aws_grafana_workspace_service_account_token.terraform[0].key, "placeholder")
}

resource "grafana_data_source" "cloudwatch" {
  count = var.enable_grafana ? 1 : 0

  type = "cloudwatch"
  name = "CloudWatch"

  json_data_encoded = jsonencode({
    defaultRegion = var.aws_region
    authType      = "default"
    sigv4Auth     = true
  })
}

# AMP 워크스페이스가 실제로 있을 때만(수동 생성 + enable_prometheus 전제) 만듦
resource "grafana_data_source" "prometheus" {
  count = var.enable_grafana && var.prometheus_workspace_arn != "" ? 1 : 0

  type = "prometheus"
  name = "Amazon Managed Prometheus"
  # ARN 형식: arn:aws:aps:region:account:workspace/ws-xxxx - workspace ID만 뽑아서 쿼리
  # 엔드포인트를 조립함(compute 모듈에 넘기는 remote_write_url과는 다른, 조회용 엔드포인트)
  url = "https://aps-workspaces.${var.aws_region}.amazonaws.com/workspaces/${element(split("/", var.prometheus_workspace_arn), 1)}"

  json_data_encoded = jsonencode({
    httpMethod    = "POST"
    sigv4Auth     = true
    sigv4AuthType = "default"
    sigv4Region   = var.aws_region
  })
}

# 상품 담당자가 매일 볼 법한 것만 최소로 - 인프라 헬스(ECS/ALB, CloudWatch는 항상 존재) +
# 앱 레벨 지표(Prometheus, AMP 연결 후에만 값이 참) 6개 패널로 제한함
locals {
  ecs_panels = [
    {
      title  = "ECS CPU Utilization (%)"
      metric = "CPUUtilization"
      x      = 0
    },
    {
      title  = "ECS Memory Utilization (%)"
      metric = "MemoryUtilization"
      x      = 12
    },
  ]

  alb_panels = [
    { title = "ALB Request Count", metric = "RequestCount", stat = "Sum", x = 0 },
    { title = "ALB Target Response Time (s)", metric = "TargetResponseTime", stat = "Average", x = 12 },
    { title = "ALB 5xx Count", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", x = 0 },
  ]

  # for 컴프리헨션으로 생성해서 ecs_panels/alb_panels와 동일하게 요소마다 같은 attribute
  # 집합을 갖게 함 - 리터럴로 2개를 따로 쓰면(legendFormat 유무 차이 등) 두 branch의 튜플
  # 타입이 갈려서 var.prometheus_workspace_arn != "" ? [...] : [] 삼항식이 "true tuple has
  # length 2, but the false tuple has length 0" 에러로 validate 자체가 실패함
  prometheus_panels = [
    {
      title  = "Backend HTTP Request Rate (by status)"
      x      = 0
      expr   = "sum(rate(dambda_http_requests_total[5m])) by (status_code)"
      legend = "{{status_code}}"
    },
    {
      title  = "Backend p95 Latency (s)"
      x      = 12
      expr   = "histogram_quantile(0.95, sum(rate(dambda_http_request_duration_seconds_bucket[5m])) by (le))"
      legend = ""
    },
  ]

  # locals는 실제로 쓰이는지(=count>0)와 무관하게 항상 계산되므로, enable_grafana=false일
  # 때 grafana_data_source.cloudwatch[0]처럼 직접 인덱싱하면 "빈 튜플" 에러가 남 - one()은
  # 0개면 null, 1개면 그 값을 돌려줘서 안전함(storage 모듈의 CloudFront 패턴과 동일)
  cloudwatch_uid = one(grafana_data_source.cloudwatch[*].uid)
  prometheus_uid = one(grafana_data_source.prometheus[*].uid)

  dashboard_json = jsonencode({
    title         = "${var.region_name} dambda 운영 대시보드"
    timezone      = "browser"
    schemaVersion = 39
    panels = concat(
      [
        for p in local.ecs_panels : {
          type       = "timeseries"
          title      = p.title
          gridPos    = { h = 8, w = 12, x = p.x, y = 0 }
          datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
          targets = [{
            # datasource/queryMode/metricQueryType/metricEditorMode: 백엔드 쿼리 API 자체는
            # 이 필드들 없이도 응답하지만(직접 API 호출로 확인함), 대시보드에 저장된 패널을
            # 여는 프론트엔드 쿼리 에디터는 이 필드들로 "빌더 모드의 일반 메트릭 쿼리"임을
            # 판단해서 쿼리를 실행함 - 없으면 쿼리 자체를 안 쏴서 No data로 보임(Explore에서
            # 직접 만든 쿼리는 UI가 이 필드들을 자동으로 채워줘서 정상 동작했던 것)
            datasource       = { type = "cloudwatch", uid = local.cloudwatch_uid }
            queryMode        = "Metrics"
            metricQueryType  = 0
            metricEditorMode = 0
            namespace        = "AWS/ECS"
            metricName       = p.metric
            statistics       = ["Average"]
            dimensions       = { ClusterName = var.ecs_cluster_name, ServiceName = var.ecs_service_name }
            region           = var.aws_region
            refId            = "A"
          }]
        }
      ],
      [
        for i, p in local.alb_panels : {
          type       = "timeseries"
          title      = p.title
          gridPos    = { h = 8, w = 12, x = p.x, y = 8 + (i >= 2 ? 8 : 0) }
          datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
          targets = [{
            datasource       = { type = "cloudwatch", uid = local.cloudwatch_uid }
            queryMode        = "Metrics"
            metricQueryType  = 0
            metricEditorMode = 0
            namespace        = "AWS/ApplicationELB"
            metricName       = p.metric
            statistics       = [p.stat]
            dimensions       = { LoadBalancer = var.alb_arn_suffix }
            region           = var.aws_region
            refId            = "A"
          }]
        }
      ],
      var.prometheus_workspace_arn != "" ? [
        for p in local.prometheus_panels : {
          type       = "timeseries"
          title      = p.title
          gridPos    = { h = 8, w = 12, x = p.x, y = 24 }
          datasource = { type = "prometheus", uid = local.prometheus_uid }
          targets = [{
            datasource   = { type = "prometheus", uid = local.prometheus_uid }
            expr         = p.expr
            legendFormat = p.legend
            range        = true
            instant      = false
            editorMode   = "code"
            refId        = "A"
          }]
        }
      ] : [],
    )
  })
}

resource "grafana_dashboard" "main" {
  count = var.enable_grafana ? 1 : 0

  config_json = local.dashboard_json
}
