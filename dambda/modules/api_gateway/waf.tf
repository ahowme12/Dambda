# API Gateway는 CloudFront와 달리 로그인/회원가입/리뷰/관리자/AI챗 등 실제 요청이 전부
# 여기로 옴 - 정적 파일만 서빙하는 CloudFront보다 실질적인 보호가 필요한 지점.
# CloudFront WAF는 us-east-1 스코프가 강제지만, API Gateway는 REGIONAL 스코프라
# API Gateway 자신과 같은 리전(서울)에 만들어야 함.
resource "aws_wafv2_web_acl" "api_gateway" {
  count = var.enable_waf ? 1 : 0

  name  = "${var.region_name}-api-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # /auth/login 무차별 대입(brute-force) 방어 - IP당 5분 동안 20회 초과 시 그 IP를 차단.
  # rate_based_statement의 limit 최소값이 100이라 경로를 좁히지 않으면 이만큼 낮게 못 잡음 -
  # scope_down_statement로 로그인 경로만 골라서 낮은 한도를 적용함
  rule {
    name     = "RateLimitLogin"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = 100
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300

        scope_down_statement {
          byte_match_statement {
            search_string         = "/auth/login"
            positional_constraint = "STARTS_WITH"
            field_to_match {
              uri_path {}
            }
            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-rate-limit-login"
      sampled_requests_enabled   = true
    }
  }

  # 전체 경로 공용 - AI챗(Bedrock 호출, 요청당 과금)을 포함한 전반적인 남용/스크래핑 방지.
  # IP당 5분에 2000회면 정상적인 앱 사용 패턴에선 절대 안 걸림
  rule {
    name     = "RateLimitGeneral"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = 2000
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-rate-limit-general"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-core-rule-set"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.region_name}-api-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.region_name}-api-waf" }
}

resource "aws_wafv2_web_acl_association" "api_gateway" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = aws_wafv2_web_acl.api_gateway[0].arn
}
