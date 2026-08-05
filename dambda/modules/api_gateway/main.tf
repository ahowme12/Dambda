resource "aws_apigatewayv2_api" "http_api_gateway" {
  name          = "${var.region_name}-api-gateway"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.cors_allowed_origins
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# VPC Link ENI 보안 그룹 (ALB는 이 SG를 소스로만 인바운드를 허용함)
resource "aws_security_group" "vpc_link_sg" {
  name   = "${var.region_name}-vpc-link-sg"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.region_name}-vpc-link-sg" }
}

# API Gateway와 내부 ALB를 연결하는 VPC Link
resource "aws_apigatewayv2_vpc_link" "main" {
  name               = "${var.region_name}-vpc-link"
  security_group_ids = [aws_security_group.vpc_link_sg.id]
  subnet_ids         = var.private_subnet_ids

  tags = { Name = "${var.region_name}-vpc-link" }
}

# ALB로 프록시하는 통합
# HTTP_PROXY 통합은 requestContext(JWT 클레임)를 자동으로 넘기지 않으므로
# authorizer가 검증한 클레임을 헤더로 다시 매핑해서 ECS 백엔드가 호출자를 식별하게 함
resource "aws_apigatewayv2_integration" "alb" {
  api_id             = aws_apigatewayv2_api.http_api_gateway.id
  integration_type   = "HTTP_PROXY"
  integration_uri    = var.alb_listener_arn
  integration_method = "ANY"
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.main.id

  request_parameters = {
    "overwrite:header.x-user-sub"   = "$context.authorizer.jwt.claims.sub"
    "overwrite:header.x-user-email" = "$context.authorizer.jwt.claims.email"
  }
}

# Cognito User Pool 발급 JWT를 검증하는 authorizer
resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http_api_gateway.id
  authorizer_type  = "JWT"
  name             = "${var.region_name}-cognito-jwt"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [var.cognito_app_client_id]
    issuer   = var.cognito_issuer_url
  }
}

# 읽기(GET)는 공개 - 로그인 없이도 콘텐츠 조회 가능
resource "aws_apigatewayv2_route" "get_root" {
  api_id    = aws_apigatewayv2_api.http_api_gateway.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_route" "get_proxy" {
  api_id    = aws_apigatewayv2_api.http_api_gateway.id
  route_key = "GET /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# 쓰기(POST/PUT/PATCH/DELETE)는 JWT 인증 필요
resource "aws_apigatewayv2_route" "write_proxy" {
  for_each = toset(["POST", "PUT", "PATCH", "DELETE"])

  api_id    = aws_apigatewayv2_api.http_api_gateway.id
  route_key = "${each.key} /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"

  authorization_type = var.require_auth ? "JWT" : "NONE"
  authorizer_id      = var.require_auth ? aws_apigatewayv2_authorizer.cognito.id : null
}

# CORS 프리플라이트(OPTIONS)는 명시적 라우트가 없으면 $default(JWT 필요)로 흘러가서
# 브라우저가 401을 받고 본 요청 자체를 못 보냄 - 프리플라이트는 스펙상 인증이 없어야 하므로
# $default보다 우선하는 전용 라우트를 인증 없이 따로 둠
resource "aws_apigatewayv2_route" "options_proxy" {
  api_id    = aws_apigatewayv2_api.http_api_gateway.id
  route_key = "OPTIONS /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

# 위에서 다루지 않은 나머지(HEAD 등)는 안전하게 기본적으로 인증 요구
resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api_gateway.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"

  authorization_type = var.require_auth ? "JWT" : "NONE"
  authorizer_id      = var.require_auth ? aws_apigatewayv2_authorizer.cognito.id : null
}

# 자동 배포 스테이지
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api_gateway.id
  name        = "$default"
  auto_deploy = true
}