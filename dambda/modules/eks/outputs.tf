output "cluster_name" {
  description = "EKS 클러스터 이름 (enable_eks=false면 빈 문자열)"
  value       = var.enable_eks ? aws_eks_cluster.main[0].name : ""
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트 (enable_eks=false면 빈 문자열)"
  value       = var.enable_eks ? aws_eks_cluster.main[0].endpoint : ""
}

