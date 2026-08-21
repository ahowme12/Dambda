# dambda(앱 인프라)가 아니라 여기(bootstrap)에 두는 이유: CloudTrail과 동일 - 예산 알림은
# dambda의 destroy/재생성 주기와 무관하게 계속 살아있어야 의미가 있음.
#
# "project" 태그로 필터링 - dambda/providers.tf와 dambda-bootstrap/main.tf의 provider가
# 둘 다 default_tags로 project=dambda를 모든 리소스에 자동으로 붙이고 있어서, 이 태그
# 하나로 두 스택의 지출을 전부 걸러낼 수 있음. 콘솔에서 Billing → Cost Allocation Tags →
# "project" 활성화를 먼저 해줘야 실제로 필터링이 동작함(활성화 전 사용량엔 소급 적용 안 됨)
resource "aws_budgets_budget" "dambda" {
  name         = "dambda-monthly"
  budget_type  = "COST"
  limit_amount = "300"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["user:project$dambda"]
  }

  # 기본값(include_credit=true)이면 크레딧이 사용량을 상쇄하는 동안 ActualSpend가 계속 $0으로
  # 잡혀서 이 budget이 사실상 무용지물이 됨(크레딧 소진 전까진 절대 안 울림) - 크레딧 유무와
  # 무관하게 "인프라가 실제로 얼마어치를 쓰고 있는지"(gross usage)를 기준으로 추적하도록 명시
  cost_types {
    include_credit = false
  }

  # 실제 지출 80% 도달 시 - 아직 여유 있을 때 미리 알림
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # 이번 달 말까지 예측한 지출이 한도를 넘길 것 같으면 - 실제로 넘기기 전에 조기 경보
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  # 실제로 한도를 넘긴 경우
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
