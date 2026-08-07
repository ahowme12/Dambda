output "workspace_endpoint" {
  description = "AMG 워크스페이스 접속 URL (Identity Center 로그인 필요)"
  value       = try("https://${aws_grafana_workspace.main[0].endpoint}", "")
}

output "workspace_id" {
  value = try(aws_grafana_workspace.main[0].id, "")
}
