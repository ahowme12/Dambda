# EKS 클러스터 IAM 롤
resource "aws_iam_role" "eks_cluster" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.region_name}-eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 클러스터 API 서버는 퍼블릭+프라이빗 서브넷 모두에 ENI를 둘 수 있게 하고(subnet_ids),
# 파드(Fargate Profile)는 아래에서 프라이빗 서브넷으로만 한정함
resource "aws_eks_cluster" "main" {
  count    = var.enable_eks ? 1 : 0
  name     = "${var.region_name}-eks-cluster"
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  vpc_config {
    subnet_ids = concat(var.public_subnet_ids, var.private_subnet_ids)
  }

  # 레거시 aws-auth ConfigMap 대신 최신 Access Entry API로 클러스터 접근 권한을 관리
  access_config {
    authentication_mode = "API"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# Fargate 파드가 시작할 때 ECR pull/로그 전송에 쓰는 실행 롤 (ECS의 execution role과 동격)
resource "aws_iam_role" "eks_fargate_pod_execution" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.region_name}-eks-fargate-pod-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_fargate_pod_execution_policy" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.eks_fargate_pod_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# kube-system용 Fargate Profile - 이게 없으면 CoreDNS가 스케줄될 노드가 없어서 DNS가
# 영원히 Pending 상태로 멈추는 잘 알려진 함정이 있음 (Fargate-only 클러스터의 필수 조치)
resource "aws_eks_fargate_profile" "kube_system" {
  count                  = var.enable_eks ? 1 : 0
  cluster_name           = aws_eks_cluster.main[0].name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = aws_iam_role.eks_fargate_pod_execution[0].arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "kube-system"
  }
}

# backend 파드가 실제로 뜨는 네임스페이스용 Fargate Profile
resource "aws_eks_fargate_profile" "app" {
  count                  = var.enable_eks ? 1 : 0
  cluster_name           = aws_eks_cluster.main[0].name
  fargate_profile_name   = "app"
  pod_execution_role_arn = aws_iam_role.eks_fargate_pod_execution[0].arn
  subnet_ids             = var.private_subnet_ids

  selector {
    namespace = "app"
  }
}

# CoreDNS 애드온 - kube-system Fargate Profile이 먼저 있어야 실제로 스케줄됨
resource "aws_eks_addon" "coredns" {
  count                       = var.enable_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_fargate_profile.kube_system]
}

# ===================== IRSA (IAM Roles for Service Accounts) =====================
# 클러스터 OIDC issuer의 TLS 인증서 지문을 가져와서 OIDC Provider를 등록 - 파드가 AWS
# API를 호출할 때 임시 자격증명을 받기 위한 연동 지점 (ECS 태스크 롤과 동격 개념)
data "tls_certificate" "eks" {
  count = var.enable_eks ? 1 : 0
  url   = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count           = var.enable_eks ? 1 : 0
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main[0].identity[0].oidc[0].issuer
}

# app 네임스페이스의 backend ServiceAccount만 이 롤을 assume할 수 있도록 조건을 검
resource "aws_iam_role" "pod_irsa" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.region_name}-eks-pod-irsa-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.eks[0].arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:sub" = "system:serviceaccount:app:backend"
          "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# ECS 태스크 롤과 완전히 동일한 런타임 권한(DynamoDB/S3/Lambda/Bedrock 등) - 정책 JSON을
# 중복 작성하지 않고 compute 모듈이 만든 정책을 그대로 attach
resource "aws_iam_role_policy_attachment" "pod_irsa_task_policy" {
  count      = var.enable_eks && var.ecs_task_policy_arn != "" ? 1 : 0
  role       = aws_iam_role.pod_irsa[0].name
  policy_arn = var.ecs_task_policy_arn
}

# ===================== 클러스터 접근 권한 (Access Entry) =====================
resource "aws_eks_access_entry" "admin" {
  for_each      = var.enable_eks ? toset(var.eks_admin_principal_arns) : toset([])
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = each.value
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = var.enable_eks ? toset(var.eks_admin_principal_arns) : toset([])
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}

# ===================== 워크로드 (Kubernetes 리소스) =====================
resource "kubernetes_namespace_v1" "app" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name = "app"
  }

  # apply를 실행하는 principal(CI 롤 또는 로컬 사용자)이 eks_admin_principal_arns에 이미
  # 등록되어 있어야 kubernetes 리소스 호출이 403 없이 통과함 - 순서 보장용 depends_on
  depends_on = [
    aws_eks_access_entry.admin,
    aws_eks_access_policy_association.admin,
    aws_eks_fargate_profile.app,
  ]
}

resource "kubernetes_service_account_v1" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.pod_irsa[0].arn
    }
  }
}

locals {
  # modules/compute의 local.container_definition environment 목록과 동일한 값들 - 같은
  # 이미지를 배포하므로 요구하는 환경변수 목록이 같음
  env_vars = var.enable_eks ? [
    { name = "PORT", value = tostring(var.container_port) },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "USER_POOL_ID", value = var.user_pool_id },
    { name = "USER_POOL_CLIENT_ID", value = var.user_pool_client_id },
    { name = "DYNAMODB_TABLE_NAME", value = var.dynamodb_table_name },
    { name = "PRODUCT_LIKES_TABLE_NAME", value = var.product_likes_table_name },
    { name = "PRODUCT_REVIEWS_TABLE_NAME", value = var.product_reviews_table_name },
    { name = "PRODUCT_CATALOG_TABLE_NAME", value = var.product_catalog_table_name },
    { name = "S3_REVIEW_PHOTOS_BUCKET", value = var.review_photos_bucket_name },
    { name = "S3_REVIEW_PHOTOS_DOMAIN", value = var.review_photos_bucket_domain },
    { name = "BEDROCK_MODEL_ID", value = var.bedrock_model_id },
    { name = "QUARANTINE_BUCKET", value = var.quarantine_bucket_name },
    { name = "REVIEW_MODERATION_QUEUE_URL", value = var.review_moderation_queue_url },
    { name = "MODERATION_EVENTS_TABLE_NAME", value = var.moderation_events_table_name },
    { name = "S3_PRODUCT_IMAGES_BUCKET", value = var.product_images_bucket_name },
    { name = "S3_PRODUCT_IMAGES_DOMAIN", value = var.product_images_bucket_domain },
  ] : []
}

resource "kubernetes_deployment_v1" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    labels    = { app = "backend" }
  }

  spec {
    replicas = 2

    selector {
      match_labels = { app = "backend" }
    }

    template {
      metadata {
        labels = { app = "backend" }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.backend[0].metadata[0].name

        container {
          name  = "app"
          image = "${var.ecr_repository_url}:latest"

          port {
            container_port = var.container_port
          }

          dynamic "env" {
            for_each = local.env_vars
            content {
              name  = env.value.name
              value = env.value.value
            }
          }
        }
      }
    }
  }

  depends_on = [aws_eks_addon.coredns]
}

# type=LoadBalancer가 AWS 쪽에 자체적으로 ELB를 프로비저닝함 - 기존 API Gateway/ALB/VPC
# Link 체인과는 완전히 분리된, 독립적으로 테스트 가능한 별도 진입점
resource "kubernetes_service_v1" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }

  spec {
    type     = "LoadBalancer"
    selector = { app = "backend" }

    port {
      port        = 80
      target_port = var.container_port
    }
  }
}
