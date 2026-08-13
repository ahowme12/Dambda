output "cluster_name" {
  description = "EKS 클러스터 이름 (enable_eks=false면 빈 문자열)"
  value       = var.enable_eks ? aws_eks_cluster.main[0].name : ""
}

output "cluster_endpoint" {
  description = "EKS API 서버 엔드포인트 (enable_eks=false면 빈 문자열)"
  value       = var.enable_eks ? aws_eks_cluster.main[0].endpoint : ""
}

# LoadBalancer 프로비저닝에 몇 분 걸릴 수 있어서 apply 직후엔 비어있을 수 있음 - 그럴 땐
# apply를 한 번 더 돌리거나 aws elbv2/elb 콘솔에서 직접 호스트네임을 확인
output "load_balancer_hostname" {
  description = "backend Service(LoadBalancer)의 외부 접속 호스트네임"
  value       = var.enable_eks ? try(kubernetes_service_v1.backend[0].status[0].load_balancer[0].ingress[0].hostname, "") : ""
}
