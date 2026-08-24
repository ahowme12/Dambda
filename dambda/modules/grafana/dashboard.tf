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

# 요청 흐름(API Gateway -> VPC Link -> ALB) + 보안(WAF) + 데이터(DynamoDB) + 비동기 파이프라인
# (review_pipeline worker Lambda) + 애플리케이션(Prometheus, 연결됐을 때만)까지 계층별로 행을
# 나눠서 구성함. 트래픽이 적어서 CPU/메모리류가 대부분 한 자릿수% 대라 - Y축을 0~100 고정 안
# 하면 auto-scale이 그 좁은 구간을 확대해서 그래프가 지그재그로 과장돼 보임. 그래서 percent류는
# min/max를 0/100으로 고정하고 thresholds로 색상 밴드를 넣어서 "지금 수치가 정상 범위 어디쯤인지"
# 한눈에 보이게 함. 구 ECS CPU/메모리 패널(AWS/ECS 네임스페이스)은 EKS 전환으로 영구히 "no data"만
# 뜨던 죽은 패널이라 이번에 완전히 제거함 - EKS 파드 리소스는 Prometheus 쪽 패널이 대신함
locals {
  # count류(Request/Errors)는 막대가, 응답시간류는 선이 더 잘 읽혀서 drawStyle을 다르게 줌.
  # 5xx는 하나라도 뜨면 바로 눈에 띄어야 해서 고정 빨강, threshold도 1 이상이면 바로 빨강
  alb_panels = [
    { title = "ALB Request Count", metric = "RequestCount", stat = "Sum", x = 0, unit = "short", drawStyle = "bars", color = "blue" },
    { title = "ALB Target Response Time (s)", metric = "TargetResponseTime", stat = "Average", x = 12, unit = "s", drawStyle = "line", color = "purple" },
    { title = "ALB 5xx Count", metric = "HTTPCode_Target_5XX_Count", stat = "Sum", x = 0, unit = "short", drawStyle = "bars", color = "red" },
  ]

  # for 컴프리헨션으로 생성해서 alb_panels와 동일하게 요소마다 같은 attribute 집합을 갖게 함 -
  # 리터럴로 2개를 따로 쓰면(legendFormat 유무 차이 등) 두 branch의 튜플 타입이 갈려서
  # var.prometheus_workspace_arn != "" ? [...] : [] 삼항식이 "true tuple has length 2, but
  # the false tuple has length 0" 에러로 validate 자체가 실패함
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

  ok_thresholds = { mode = "absolute", steps = [{ value = null, color = "green" }] }

  # 행(row) 패널 - 접었다 펼 수 있는 섹션 헤더로 대시보드를 계층별로 구획해서 스크롤만 해도
  # "지금 뭘 보고 있는지" 한눈에 들어오게 함
  row = { type = "row", collapsed = false, panels = [] }

  cloudwatch_metric_panel = {
    type       = "timeseries"
    datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
  }

  # 단일 CloudWatch 지표 타겟 하나를 만드는 공통 빌더 - alb_panels 등 for 컴프리헨션과
  # 별개로, 시리즈 2개짜리 패널(WAF 허용/차단, Lambda 호출/에러 등)에서 재사용
  cw_target = {
    id               = ""
    logGroups        = []
    queryMode        = "Metrics"
    expression       = ""
    period           = ""
    metricQueryType  = 0
    metricEditorMode = 0
    sqlExpression    = ""
    matchExact       = true
    hide             = false
  }

  dashboard_json = jsonencode({
    title         = "${var.region_name} dambda 운영 대시보드"
    timezone      = "browser"
    schemaVersion = 39
    # panels 리스트는 섹션마다 모양이 다른 객체(행 헤더 vs 메트릭 패널, 타겟 1개 vs 2개 등)를
    # concat()으로 섞다 보니, HCL이 상수 폴딩 가능한 concat() 결과를 고정 길이 tuple로 좁게
    # 추론해버려서 "삼항식의 true/false 타입이 안 맞는다"(tuple has length N vs 0) 에러가 남
    # (alb_panels 주석에 남아있는 그 문제의 확장판) - tolist()로 각 섹션의 concat() 결과를
    # 명시적으로 list 타입으로 넓혀서(tuple의 정확한 길이 정보를 지워서) 우회함
    panels = concat(
      # ===== 행 1: 트래픽 (API Gateway -> ALB) =====
      [merge(local.row, { title = "트래픽", gridPos = { h = 1, w = 24, x = 0, y = 0 } })],
      var.api_gateway_id != "" ? [
        merge(local.cloudwatch_metric_panel, {
          title   = "API Gateway Request Count"
          gridPos = { h = 8, w = 12, x = 0, y = 1 }
          fieldConfig = {
            defaults = merge(local.base_field_defaults, {
              unit       = "short"
              color      = { mode = "fixed", fixedColor = "blue" }
              custom     = merge(local.base_field_defaults.custom, { drawStyle = "bars" })
              thresholds = local.ok_thresholds
            })
            overrides = []
          }
          targets = [merge(local.cw_target, {
            region     = var.aws_region
            namespace  = "AWS/ApiGateway"
            metricName = "Count"
            dimensions = { ApiId = var.api_gateway_id, Stage = "$default" }
            statistic  = "Sum"
            datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
            refId      = "A"
            label      = ""
          })]
        }),
        merge(local.cloudwatch_metric_panel, {
          title   = "API Gateway 4xx / 5xx"
          gridPos = { h = 8, w = 12, x = 12, y = 1 }
          fieldConfig = {
            defaults = merge(local.base_field_defaults, {
              unit       = "short"
              color      = { mode = "palette-classic" }
              custom     = merge(local.base_field_defaults.custom, { drawStyle = "bars" })
              thresholds = { mode = "absolute", steps = [{ value = null, color = "green" }, { value = 1, color = "red" }] }
            })
            overrides = []
          }
          targets = [
            merge(local.cw_target, {
              region     = var.aws_region
              namespace  = "AWS/ApiGateway"
              metricName = "4xx"
              dimensions = { ApiId = var.api_gateway_id, Stage = "$default" }
              statistic  = "Sum"
              datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
              refId      = "A"
              label      = "4xx"
            }),
            merge(local.cw_target, {
              region     = var.aws_region
              namespace  = "AWS/ApiGateway"
              metricName = "5xx"
              dimensions = { ApiId = var.api_gateway_id, Stage = "$default" }
              statistic  = "Sum"
              datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
              refId      = "B"
              label      = "5xx"
            }),
          ]
        }),
      ] : [],
      [
        for i, p in local.alb_panels : merge(local.cloudwatch_metric_panel, {
          title   = p.title
          gridPos = { h = 8, w = 12, x = p.x, y = 9 + (i >= 2 ? 8 : 0) }
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
              } : local.ok_thresholds
            })
            overrides = []
          }
          targets = [merge(local.cw_target, {
            region     = var.aws_region
            namespace  = "AWS/ApplicationELB"
            metricName = p.metric
            dimensions = { LoadBalancer = var.alb_arn_suffix }
            statistic  = p.stat
            datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
            refId      = "A"
            label      = ""
          })]
        })
      ],

      # ===== 행 2: 보안 (WAF) =====
      var.waf_web_acl_name != "" ? tolist(concat(
        [merge(local.row, { title = "보안 (WAF)", gridPos = { h = 1, w = 24, x = 0, y = 25 } })],
        [
          merge(local.cloudwatch_metric_panel, {
            title   = "WAF Allowed vs Blocked Requests"
            gridPos = { h = 8, w = 24, x = 0, y = 26 }
            fieldConfig = {
              defaults = merge(local.base_field_defaults, {
                unit       = "short"
                color      = { mode = "palette-classic" }
                custom     = merge(local.base_field_defaults.custom, { drawStyle = "bars", stacking = { mode = "normal", group = "A" } })
                thresholds = local.ok_thresholds
              })
              overrides = []
            }
            targets = [
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/WAFV2"
                metricName = "AllowedRequests"
                dimensions = { WebACL = var.waf_web_acl_name, Rule = "ALL", Region = var.aws_region }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "A"
                label      = "Allowed"
              }),
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/WAFV2"
                metricName = "BlockedRequests"
                dimensions = { WebACL = var.waf_web_acl_name, Rule = "ALL", Region = var.aws_region }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "B"
                label      = "Blocked"
              }),
            ]
          })
        ]
      )) : [],

      # ===== 행 3: 데이터베이스 (DynamoDB) =====
      var.product_catalog_table_name != "" ? tolist(concat(
        [merge(local.row, { title = "데이터베이스 (product_catalog)", gridPos = { h = 1, w = 24, x = 0, y = 35 } })],
        [
          merge(local.cloudwatch_metric_panel, {
            title   = "Consumed Capacity Units (Read/Write)"
            gridPos = { h = 8, w = 12, x = 0, y = 36 }
            fieldConfig = {
              defaults  = merge(local.base_field_defaults, { unit = "short", color = { mode = "palette-classic" }, thresholds = local.ok_thresholds })
              overrides = []
            }
            targets = [
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/DynamoDB"
                metricName = "ConsumedReadCapacityUnits"
                dimensions = { TableName = var.product_catalog_table_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "A"
                label      = "Read"
              }),
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/DynamoDB"
                metricName = "ConsumedWriteCapacityUnits"
                dimensions = { TableName = var.product_catalog_table_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "B"
                label      = "Write"
              }),
            ]
          }),
          merge(local.cloudwatch_metric_panel, {
            title   = "Throttled Requests (Read/Write)"
            gridPos = { h = 8, w = 12, x = 12, y = 36 }
            fieldConfig = {
              defaults = merge(local.base_field_defaults, {
                unit       = "short"
                color      = { mode = "palette-classic" }
                thresholds = { mode = "absolute", steps = [{ value = null, color = "green" }, { value = 1, color = "red" }] }
              })
              overrides = []
            }
            targets = [
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/DynamoDB"
                metricName = "ReadThrottleEvents"
                dimensions = { TableName = var.product_catalog_table_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "A"
                label      = "Read"
              }),
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/DynamoDB"
                metricName = "WriteThrottleEvents"
                dimensions = { TableName = var.product_catalog_table_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "B"
                label      = "Write"
              }),
            ]
          }),
        ]
      )) : [],

      # ===== 행 4: 비동기 파이프라인 (리뷰 검열 worker Lambda) =====
      var.review_pipeline_worker_function_name != "" ? tolist(concat(
        [merge(local.row, { title = "비동기 파이프라인 (리뷰 검열)", gridPos = { h = 1, w = 24, x = 0, y = 44 } })],
        [
          merge(local.cloudwatch_metric_panel, {
            title   = "Worker Invocations / Errors"
            gridPos = { h = 8, w = 12, x = 0, y = 45 }
            fieldConfig = {
              defaults = merge(local.base_field_defaults, {
                unit       = "short"
                color      = { mode = "palette-classic" }
                custom     = merge(local.base_field_defaults.custom, { drawStyle = "bars" })
                thresholds = { mode = "absolute", steps = [{ value = null, color = "green" }, { value = 1, color = "red" }] }
              })
              overrides = []
            }
            targets = [
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/Lambda"
                metricName = "Invocations"
                dimensions = { FunctionName = var.review_pipeline_worker_function_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "A"
                label      = "Invocations"
              }),
              merge(local.cw_target, {
                region     = var.aws_region
                namespace  = "AWS/Lambda"
                metricName = "Errors"
                dimensions = { FunctionName = var.review_pipeline_worker_function_name }
                statistic  = "Sum"
                datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
                refId      = "B"
                label      = "Errors"
              }),
            ]
          }),
          merge(local.cloudwatch_metric_panel, {
            title   = "Worker Duration (ms)"
            gridPos = { h = 8, w = 12, x = 12, y = 45 }
            fieldConfig = {
              defaults  = merge(local.base_field_defaults, { unit = "ms", color = { mode = "fixed", fixedColor = "purple" }, thresholds = local.ok_thresholds })
              overrides = []
            }
            targets = [merge(local.cw_target, {
              region     = var.aws_region
              namespace  = "AWS/Lambda"
              metricName = "Duration"
              dimensions = { FunctionName = var.review_pipeline_worker_function_name }
              statistic  = "Average"
              datasource = { type = "cloudwatch", uid = local.cloudwatch_uid }
              refId      = "A"
              label      = ""
            })]
          }),
        ]
      )) : [],

      # ===== 행 5: 애플리케이션 (Prometheus, AMP 연결됐을 때만) =====
      var.prometheus_workspace_arn != "" ? tolist(concat(
        [merge(local.row, { title = "애플리케이션", gridPos = { h = 1, w = 24, x = 0, y = 53 } })],
        [
          for p in local.prometheus_panels : {
            type       = "timeseries"
            title      = p.title
            gridPos    = { h = 8, w = 12, x = p.x, y = 54 }
            datasource = { type = "prometheus", uid = local.prometheus_uid }
            fieldConfig = {
              defaults = merge(local.base_field_defaults, {
                unit  = p.unit
                color = { mode = p.title == "Backend HTTP Request Rate (by status)" ? "palette-classic" : "fixed", fixedColor = p.color }
                thresholds = p.title == "Backend p95 Latency (s)" ? {
                  mode  = "absolute"
                  steps = [{ value = null, color = "green" }, { value = 0.5, color = "yellow" }, { value = 1, color = "red" }]
                } : local.ok_thresholds
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
        ]
      )) : [],
    )
  })
}

resource "grafana_dashboard" "main" {
  count = var.enable_grafana ? 1 : 0

  config_json = local.dashboard_json
}
