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
# 앱 레벨 지표(Prometheus, AMP 연결 후에만 값이 참) 6개 패널로 제한함. 트래픽이 적어서
# CPU/메모리가 대부분 한 자릿수% 대라 - Y축을 0~100 고정 안 하면 auto-scale이 그 좁은 구간을
# 확대해서 그래프가 지그재그로 과장돼 보임. 그래서 percent류는 min/max를 0/100으로 고정하고
# thresholds로 색상 밴드를 넣어서 "지금 수치가 정상 범위 어디쯤인지" 한눈에 보이게 함
locals {
  ecs_panels = [
    { title = "ECS CPU Utilization (%)", metric = "CPUUtilization", x = 0, color = "blue" },
    { title = "ECS Memory Utilization (%)", metric = "MemoryUtilization", x = 12, color = "purple" },
  ]

  # count류(Request/5xx)는 막대가, 연속값(응답시간)은 선이 더 잘 읽혀서 drawStyle을 다르게 줌.
  # 5xx는 하나라도 뜨면 바로 눈에 띄어야 해서 고정 빨강, threshold도 1 이상이면 바로 빨강
  alb_panels = [
    { title = "ALB Request Count", metric = "RequestCount", stat = "Sum", x = 0, unit = "short", drawStyle = "bars", color = "blue" },
    { title = "ALB Target Response Time (s)", metric = "TargetResponseTime", stat = "Average", x = 12, unit = "s", drawStyle = "line", color = "purple" },
    { title = "ALB 5xx Count", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", x = 0, unit = "short", drawStyle = "bars", color = "red" },
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
      unit   = "reqps"
      color  = "blue"
    },
    {
      title  = "Backend p95 Latency (s)"
      x      = 12
      expr   = "histogram_quantile(0.95, sum(rate(dambda_http_request_duration_seconds_bucket[5m])) by (le))"
      legend = ""
      unit   = "s"
      color  = "purple"
    },
  ]

  # locals는 실제로 쓰이는지(=count>0)와 무관하게 항상 계산되므로, enable_grafana=false일
  # 때 grafana_data_source.cloudwatch[0]처럼 직접 인덱싱하면 "빈 튜플" 에러가 남 - one()은
  # 0개면 null, 1개면 그 값을 돌려줘서 안전함(storage 모듈의 CloudFront 패턴과 동일)
  cloudwatch_uid = one(grafana_data_source.cloudwatch[*].uid)
  prometheus_uid = one(grafana_data_source.prometheus[*].uid)

  # 패널 공통 룩앤필 - 선 아래 은은한 그라데이션 채움 + 부드러운 곡선. 개별 패널은 이 위에
  # unit/min/max/thresholds/color만 덮어씀
  base_field_defaults = {
    custom = {
      drawStyle         = "line"
      lineInterpolation = "smooth"
      lineWidth         = 2
      fillOpacity       = 15
      gradientMode      = "opacity"
      showPoints        = "never"
      spanNulls         = false
      thresholdsStyle   = { mode = "area" }
      axisPlacement     = "auto"
      stacking          = { mode = "none", group = "A" }
      scaleDistribution = { type = "linear" }
    }
  }

  percent_thresholds = {
    mode = "absolute"
    steps = [
      { value = null, color = "green" },
      { value = 70, color = "yellow" },
      { value = 90, color = "red" },
    ]
  }

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
          fieldConfig = {
            defaults = merge(local.base_field_defaults, {
              unit       = "percent"
              min        = 0
              max        = 100
              color      = { mode = "fixed", fixedColor = p.color }
              thresholds = local.percent_thresholds
            })
            overrides = []
          }
          targets = [{
            # Grafana UI로 직접 만든(정상 동작하는) 패널의 Panel JSON을 그대로 떠서 맞춘 필드
            # 구성 - 특히 "statistics"(배열, 구버전 필드명)가 아니라 "statistic"(단수)이어야
            # 프론트엔드가 이 타겟을 "완전한 쿼리"로 인식해서 실행함. 백엔드 쿼리 API 자체는
            # statistics(배열)도 관대하게 받아줘서 직접 API 호출로는 정상 응답했었지만, 브라우저
            # 패널 렌더링은 이 필드명이 안 맞으면 쿼리 자체를 안 쏴서 No data로만 보였던 것
            id               = ""
            region           = var.aws_region
            logGroups        = []
            queryMode        = "Metrics"
            namespace        = "AWS/ECS"
            metricName       = p.metric
            expression       = ""
            dimensions       = { ClusterName = var.ecs_cluster_name, ServiceName = var.ecs_service_name }
            statistic        = "Average"
            period           = ""
            metricQueryType  = 0
            metricEditorMode = 0
            sqlExpression    = ""
            matchExact       = true
            datasource       = { type = "cloudwatch", uid = local.cloudwatch_uid }
            refId            = "A"
            label            = ""
            hide             = false
          }]
        }
      ],
      [
        for i, p in local.alb_panels : {
          type       = "timeseries"
          title      = p.title
          gridPos    = { h = 8, w = 12, x = p.x, y = 8 + (i >= 2 ? 8 : 0) }
          datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
          fieldConfig = {
            defaults = merge(local.base_field_defaults, {
              unit   = p.unit
              color  = { mode = "fixed", fixedColor = p.color }
              custom = merge(local.base_field_defaults.custom, { drawStyle = p.drawStyle })
              thresholds = p.title == "ALB 5xx Count" ? {
                mode  = "absolute"
                steps = [{ value = null, color = "green" }, { value = 1, color = "red" }]
                } : p.title == "ALB Target Response Time (s)" ? {
                mode  = "absolute"
                steps = [{ value = null, color = "green" }, { value = 0.5, color = "yellow" }, { value = 1, color = "red" }]
              } : { mode = "absolute", steps = [{ value = null, color = p.color }] }
            })
            overrides = []
          }
          targets = [{
            id               = ""
            region           = var.aws_region
            logGroups        = []
            queryMode        = "Metrics"
            namespace        = "AWS/ApplicationELB"
            metricName       = p.metric
            expression       = ""
            dimensions       = { LoadBalancer = var.alb_arn_suffix }
            statistic        = p.stat
            period           = ""
            metricQueryType  = 0
            metricEditorMode = 0
            sqlExpression    = ""
            matchExact       = true
            datasource       = { type = "cloudwatch", uid = local.cloudwatch_uid }
            refId            = "A"
            label            = ""
            hide             = false
          }]
        }
      ],
      var.prometheus_workspace_arn != "" ? [
        for p in local.prometheus_panels : {
          type       = "timeseries"
          title      = p.title
          gridPos    = { h = 8, w = 12, x = p.x, y = 24 }
          datasource = { type = "prometheus", uid = local.prometheus_uid }
          fieldConfig = {
            defaults = merge(local.base_field_defaults, {
              unit  = p.unit
              color = { mode = p.title == "Backend HTTP Request Rate (by status)" ? "palette-classic" : "fixed", fixedColor = p.color }
              thresholds = p.title == "Backend p95 Latency (s)" ? {
                mode  = "absolute"
                steps = [{ value = null, color = "green" }, { value = 0.5, color = "yellow" }, { value = 1, color = "red" }]
              } : { mode = "absolute", steps = [{ value = null, color = "green" }] }
            })
            overrides = []
          }
          targets = [{
            datasource   = { type = "prometheus", uid = local.prometheus_uid }
            expr         = p.expr
            legendFormat = p.legend
            range        = true
            instant      = false
            editorMode   = "code"
            queryType    = "range"
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
