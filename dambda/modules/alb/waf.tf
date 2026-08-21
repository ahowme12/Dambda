# internal ALB에 WAFv2를 붙임 - API Gateway 스테이지 throttle(default_route_settings)은
# 전체 트래픽 합산 기준이라 악성 IP 하나가 그 한도를 다 써버리면 정상 사용자까지 막히는
# 구조적 약점이 있음(api_gateway 모듈 주석 참고). WAF의 Rate-based Rule은 IP별로 개별
# 집계돼서 가해자만 골라 막을 수 있음 - 두 계층이 서로 다른 문제를 풀어서 대체가 아니라 보완.
resource "aws_wafv2_web_acl" "alb" {
  count = var.enable_waf ? 1 : 0
  name  = "${var.region_name}-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # 1) AWS 관리형 룰 - 경로순회/비정상 헤더 등 일반적인 공격 패턴
  rule {
    name     = "AWS-CommonRuleSet"
    priority = 0

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
      metric_name                = "${var.region_name}-waf-common"
      sampled_requests_enabled   = true
    }
  }

  # 2) AWS 관리형 룰 - Log4Shell류 알려진 CVE 익스플로잇 시그니처
  rule {
    name     = "AWS-KnownBadInputs"
    priority = 1

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
      metric_name                = "${var.region_name}-waf-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # 3) AWS 관리형 룰 - 알려진 악성 IP/봇넷 평판 목록
  rule {
    name     = "AWS-IpReputation"
    priority = 2

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
      metric_name                = "${var.region_name}-waf-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # 4) /products로 가는 POST(상품 Q&A "/ask", 추천 "/recommend", 좋아요) - 여기 상당수가
  # Bedrock 호출이라 요청 1건이 곧 실비용임. WAF 최소 허용치(5분당 100건)로 강하게 제한
  rule {
    name     = "RateLimit-ProductsPost"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string = "/products"
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "STARTS_WITH"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                search_string = "POST"
                field_to_match {
                  method {}
                }
                positional_constraint = "EXACTLY"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-waf-rate-products-post"
      sampled_requests_enabled   = true
    }
  }

  # 5) /auth로 가는 POST(로그인/가입/토큰갱신) - 크리덴셜 스터핑/무차별 대입 방어
  rule {
    name     = "RateLimit-AuthPost"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"

        scope_down_statement {
          and_statement {
            statement {
              byte_match_statement {
                search_string = "/auth"
                field_to_match {
                  uri_path {}
                }
                positional_constraint = "STARTS_WITH"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                search_string = "POST"
                field_to_match {
                  method {}
                }
                positional_constraint = "EXACTLY"
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-waf-rate-auth-post"
      sampled_requests_enabled   = true
    }
  }

  # 6) 그 외 전체 경로 - 위 두 개보다 훨씬 여유 있게(5분당 2000건/IP), 정상적인 상품 조회
  # 트래픽은 절대 안 걸리고 명백한 봇/스크래핑만 잡아내는 느슨한 안전망
  rule {
    name     = "RateLimit-General"
    priority = 5

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.region_name}-waf-rate-general"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.region_name}-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = { Name = "${var.region_name}-alb-waf" }
}

resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.enable_waf ? 1 : 0
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.alb[0].arn
}
