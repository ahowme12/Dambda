output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.main.arn
}

output "app_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "issuer_url" {
  description = "API Gateway JWT Authorizer의 issuer 값"
  value       = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
