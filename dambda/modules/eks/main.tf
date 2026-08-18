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

# backend_foundation 모듈이 만든 것과 완전히 동일한 런타임 권한(DynamoDB/S3/Lambda/Bedrock/
# AMP RemoteWrite 등) - 정책 JSON을 중복 작성하지 않고 그 정책을 그대로 attach
resource "aws_iam_role_policy_attachment" "pod_irsa_task_policy" {
  count      = var.enable_eks && var.backend_task_policy_arn != "" ? 1 : 0
  role       = aws_iam_role.pod_irsa[0].name
  policy_arn = var.backend_task_policy_arn
}

# ADOT 사이드카의 awsxray exporter가 IRSA 자격증명 체인으로 X-Ray에 트레이스를 보내는 데
# 필요함 - AWS 관리형 정책 그대로 사용(예전 ECS task role의 task_xray attachment와 동일 패턴),
# 커스텀 backend_task_policy에 안 섞음
resource "aws_iam_role_policy_attachment" "pod_irsa_xray" {
  count      = var.enable_eks && var.enable_tracing ? 1 : 0
  role       = aws_iam_role.pod_irsa[0].name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
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

# Tavily API 키(SecureString) - ECS는 실행 롤이 컨테이너 시작 시점에 SSM에서 직접 주입해줬지만
# EKS엔 그 메커니즘이 없어서, Terraform이 값을 읽어 k8s Secret으로 만들고 env로 연결함
data "aws_ssm_parameter" "tavily" {
  count           = var.enable_eks && var.tavily_api_key_ssm_name != "" ? 1 : 0
  name            = var.tavily_api_key_ssm_name
  with_decryption = true
}

resource "kubernetes_secret_v1" "backend" {
  count = var.enable_eks && var.tavily_api_key_ssm_name != "" ? 1 : 0
  metadata {
    name      = "backend-secrets"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }
  data = {
    TAVILY_API_KEY = data.aws_ssm_parameter.tavily[0].value
  }
}

locals {
  # backend_foundation을 통해 재사용하는 이미지가 요구하는 환경변수 목록 - ECS 시절과 동일
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
    { name = "BEDROCK_EMBEDDING_MODEL_ID", value = var.bedrock_embedding_model_id },
    { name = "QUARANTINE_BUCKET", value = var.quarantine_bucket_name },
    { name = "REVIEW_MODERATION_QUEUE_URL", value = var.review_moderation_queue_url },
    { name = "MODERATION_EVENTS_TABLE_NAME", value = var.moderation_events_table_name },
    { name = "S3_PRODUCT_IMAGES_BUCKET", value = var.product_images_bucket_name },
    { name = "S3_PRODUCT_IMAGES_DOMAIN", value = var.product_images_bucket_domain },
    { name = "ENABLE_TRACING", value = tostring(var.enable_tracing) },
  ] : []

  # ECS 태스크(cpu=512/memory=1024)와 동일한 파드 사이징 - Fargate 파드 스케줄링과 HPA의
  # CPU % 계산 둘 다 requests 기준이라 필수
  app_resources = {
    requests = { cpu = "500m", memory = "1024Mi" }
    limits   = { memory = "1024Mi" }
  }

  # modules/compute의 ADOT 구성을 그대로 포팅 - 같은 파드 안 두 번째 컨테이너로 앱의
  # 127.0.0.1:9090/metrics를 긁어 AMP로 SigV4 remote-write함 (동일 네트워크 네임스페이스라
  # 파드 안에서는 로컬호스트로 통신 가능 - ECS awsvpc 태스크와 동일한 성질)
  adot_receivers = merge(
    {
      prometheus = {
        config = {
          scrape_configs = [{
            job_name        = "dambda-backend"
            scrape_interval = "30s"
            static_configs  = [{ targets = ["127.0.0.1:9090"] }]
          }]
        }
      }
    },
    var.enable_tracing ? {
      otlp = { protocols = { http = { endpoint = "0.0.0.0:4318" } } }
    } : {}
  )

  adot_exporters = merge(
    {
      prometheusremotewrite = {
        endpoint = var.prometheus_remote_write_url
        auth     = { authenticator = "sigv4auth" }
      }
    },
    var.enable_tracing ? { awsxray = {} } : {}
  )

  adot_pipelines = merge(
    { metrics = { receivers = ["prometheus"], exporters = ["prometheusremotewrite"] } },
    var.enable_tracing ? { traces = { receivers = ["otlp"], exporters = ["awsxray"] } } : {}
  )

  adot_config = yamlencode({
    extensions = {
      sigv4auth = { region = var.aws_region, service = "aps" }
    }
    receivers = local.adot_receivers
    exporters = local.adot_exporters
    service = {
      extensions = ["sigv4auth"]
      pipelines  = local.adot_pipelines
    }
  })
}

resource "kubernetes_deployment_v1" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    labels    = { app = "backend" }
  }

  spec {
    # HPA(modules/eks의 kubernetes_horizontal_pod_autoscaler_v2)가 이후 이 값을 계속 바꾸므로,
    # 여기서는 초기값만 주고 apply할 때마다 HPA가 정한 값을 덮어쓰지 않도록 무시함
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

          dynamic "env" {
            for_each = var.tavily_api_key_ssm_name != "" ? [1] : []
            content {
              name = "TAVILY_API_KEY"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret_v1.backend[0].metadata[0].name
                  key  = "TAVILY_API_KEY"
                }
              }
            }
          }

          resources {
            requests = local.app_resources.requests
            limits   = local.app_resources.limits
          }
        }

        dynamic "container" {
          for_each = var.enable_prometheus ? [1] : []
          content {
            name  = "adot-collector"
            image = "public.ecr.aws/aws-observability/aws-otel-collector:latest"

            env {
              name  = "AOT_CONFIG_CONTENT"
              value = local.adot_config
            }

            resources {
              requests = { cpu = "50m", memory = "128Mi" }
              limits   = { memory = "128Mi" }
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [spec[0].replicas]
    precondition {
      condition     = !var.enable_tracing || var.enable_prometheus
      error_message = "enable_tracing=true이면 enable_prometheus도 true여야 합니다 (ADOT 사이드카를 같이 씀)."
    }
  }

  depends_on = [aws_eks_addon.coredns]
}

# 기존 API Gateway/ALB/VPC Link/Cognito 인증 체인을 그대로 재사용하기 위해 ClusterIP로 두고,
# 아래 TargetGroupBinding이 이 Service 뒤의 파드 IP를 기존 ALB 대상 그룹에 직접 등록함
# (독자적인 LoadBalancer/ELB를 새로 만들지 않음)
resource "kubernetes_service_v1" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }

  spec {
    type     = "ClusterIP"
    selector = { app = "backend" }

    port {
      port        = 80
      target_port = var.container_port
    }
  }
}

# AWS Load Balancer Controller가 제공하는 CRD - 이 Service 뒤 파드 IP들을 기존 ALB 대상
# 그룹(target_type=ip)에 직접 등록해줌. 신규 클러스터에서는 helm_release.aws_load_balancer_controller가
# CRD를 먼저 설치해야 이 리소스가 plan/apply될 수 있어서, 최초 1회는 2단계 apply가 필요함
# (README/PR 설명에 명시 - Grafana IAM Identity Center 사전조건과 같은 성격의 제약)
resource "kubernetes_manifest" "backend_target_group_binding" {
  count = var.enable_eks ? 1 : 0
  manifest = {
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = "backend"
      namespace = kubernetes_namespace_v1.app[0].metadata[0].name
    }
    spec = {
      targetGroupARN = var.alb_target_group_arn
      targetType     = "ip"
      serviceRef = {
        name = kubernetes_service_v1.backend[0].metadata[0].name
        port = var.container_port
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# EKS Fargate는 ECS와 달리 파드 로그가 자동으로 CloudWatch에 안 감 - kube-system의
# aws-logging ConfigMap으로 Fluent Bit 라우팅을 명시해야 함(Fargate 로깅의 표준 방식)
resource "kubernetes_config_map_v1" "aws_logging" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "aws-logging"
    namespace = "kube-system"
  }

  data = {
    "output.conf" = <<-EOT
      [OUTPUT]
          Name cloudwatch_logs
          Match *
          region ${var.aws_region}
          log_group_name ${var.backend_log_group_name}
          log_stream_prefix fargate-
          auto_create_group false
    EOT
  }

  depends_on = [aws_eks_fargate_profile.kube_system]
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "backend" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }

  spec {
    min_replicas = 2
    # ECS aws_appautoscaling_target(autoscaling_max_capacity)과 동일한 상한
    max_replicas = 5

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.backend[0].metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type = "Utilization"
          # ECS aws_appautoscaling_policy의 target_value=60.0과 동일한 기준
          average_utilization = 60
        }
      }
    }
  }

  depends_on = [helm_release.metrics_server]
}

# ===================== AWS Load Balancer Controller (IRSA + helm) =====================
# 기존 ALB 대상 그룹에 파드 IP를 등록해주는 컨트롤러 - TargetGroupBinding CRD를 제공함.
# 새 ELB를 만드는 게 아니라 "이미 있는 대상 그룹을 관리"하는 용도로만 씀(Ingress는 안 씀)
resource "aws_iam_role" "alb_controller" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.region_name}-alb-controller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.eks[0].arn }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(aws_iam_openid_connect_provider.eks[0].url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# AWS가 공식 배포하는 AWSLoadBalancerControllerIAMPolicy 그대로(eks-charts 저장소 기준) -
# 컨트롤러가 ALB/NLB/대상그룹/보안그룹을 관리하는 데 필요한 전체 권한 세트
resource "aws_iam_policy" "alb_controller" {
  count       = var.enable_eks ? 1 : 0
  name        = "${var.region_name}-alb-controller-policy"
  description = "AWS Load Balancer Controller IAM policy (공식 배포본)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes", "ec2:DescribeAddresses", "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways", "ec2:DescribeVpcs", "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups", "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces", "ec2:DescribeTags", "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools", "ec2:GetSecurityGroupsForVpc", "ec2:DescribeIpamPools",
          "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies", "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores", "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient", "acm:ListCertificates", "acm:DescribeCertificate",
          "iam:ListServerCertificates", "iam:GetServerCertificate",
          "waf-regional:GetWebACL", "waf-regional:GetWebACLForResource", "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL", "wafv2:GetWebACL", "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL", "wafv2:DisassociateWebACL", "shield:GetSubscriptionState",
          "shield:DescribeProtection", "shield:CreateProtection", "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = ["ec2:CreateTags"]
        Resource  = "arn:aws:ec2:*:*:security-group/*"
        Condition = { StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }, Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect    = "Allow"
        Action    = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource  = "arn:aws:ec2:*:*:security-group/*"
        Condition = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "true", "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect    = "Allow"
        Action    = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress", "ec2:DeleteSecurityGroup"]
        Resource  = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource  = "*"
        Condition = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule", "elasticloadbalancing:DeleteRule",
        ]
        Resource = "*"
      },
      {
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource  = ["arn:aws:elasticloadbalancing:*:*:targetgroup/*/*", "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*", "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"]
        Condition = { Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "true", "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = ["arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*", "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*", "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*", "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups", "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes", "elasticloadbalancing:ModifyCapacityReservation",
          "elasticloadbalancing:ModifyIpPools",
        ]
        Resource  = "*"
        Condition = { Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" } }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl", "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates", "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.alb_controller[0].name
  policy_arn = aws_iam_policy.alb_controller[0].arn
}

resource "kubernetes_service_account_v1" "alb_controller" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller[0].arn
    }
  }
  depends_on = [aws_eks_fargate_profile.kube_system]
}

resource "helm_release" "aws_load_balancer_controller" {
  count      = var.enable_eks ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set = [
    { name = "clusterName", value = aws_eks_cluster.main[0].name },
    { name = "region", value = var.aws_region },
    { name = "vpcId", value = var.vpc_id },
    { name = "serviceAccount.create", value = "false" },
    { name = "serviceAccount.name", value = kubernetes_service_account_v1.alb_controller[0].metadata[0].name },
  ]

  depends_on = [
    aws_eks_addon.coredns,
    aws_iam_role_policy_attachment.alb_controller,
  ]
}

# Fargate-only 클러스터엔 metrics-server가 기본으로 없어서 HPA가 CPU %를 계산할 방법이 없음
resource "helm_release" "metrics_server" {
  count      = var.enable_eks ? 1 : 0
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  depends_on = [aws_eks_fargate_profile.kube_system]
}
