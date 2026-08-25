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

# k8s Secret(예: TAVILY_API_KEY)이 etcd에 평문급으로 저장되는 걸 막기 위한 봉투암호화용 키.
# aws/ssm 같은 AWS 관리형 키를 재사용하지 않고 전용 CMK를 두는 이유: EKS Secret 암호화는
# 키 정책/로테이션을 독립적으로 관리하는 게 맞음(다른 용도와 섞이면 키 삭제/정책 변경 시
# 영향 범위 파악이 어려워짐)
resource "aws_kms_key" "eks_secrets" {
  count               = var.enable_eks ? 1 : 0
  description         = "EKS Secrets 봉투암호화 키 (${var.region_name}-eks-cluster)"
  enable_key_rotation = true
}

resource "aws_kms_alias" "eks_secrets" {
  count         = var.enable_eks ? 1 : 0
  name          = "alias/${var.region_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets[0].key_id
}

# 컨트롤플레인 감사 로그(api/audit/authenticator) 대상 로그 그룹 - EKS가 로깅 활성화 시
# 자동으로 이 정확한 이름으로 로그 그룹을 만들지만, 보존기간을 관리하려고 미리 명시적으로
# 만들어둠(backend_foundation 모듈과 동일하게 30일 보존)
resource "aws_cloudwatch_log_group" "eks_cluster" {
  count             = var.enable_eks ? 1 : 0
  name              = "/aws/eks/${var.region_name}-eks-cluster/cluster"
  retention_in_days = 30
}

# 클러스터 API 서버는 퍼블릭+프라이빗 서브넷 모두에 ENI를 둘 수 있게 하고(subnet_ids),
# 파드(Fargate Profile)는 아래에서 프라이빗 서브넷으로만 한정함
resource "aws_eks_cluster" "main" {
  count    = var.enable_eks ? 1 : 0
  name     = "${var.region_name}-eks-cluster"
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster[0].arn

  # api/audit/authenticator만 켬(controllerManager/scheduler는 노이즈만 많고 감사 목적엔
  # 잘 안 씀) - 누가 언제 클러스터 API를 호출했는지 CloudWatch Logs에 남게 됨
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  vpc_config {
    subnet_ids             = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access = true
    # CI(GitHub-hosted 러너)/로컬 kubectl이 퍼블릭 IP로 붙어야 해서 public은 유지하되,
    # VPC 내부 트래픽은 인터넷을 안 거치도록 private도 같이 켬(AWS 권장 구성)
    endpoint_private_access = true
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets[0].arn
    }
  }

  # 레거시 aws-auth ConfigMap 대신 최신 Access Entry API로 클러스터 접근 권한을 관리
  access_config {
    authentication_mode = "API"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

# Fargate로 뜨는 파드는 (별도 Security Groups for Pods 설정이 없는 한) 전부 이 클러스터
# 보안그룹을 그대로 씀. AWS가 자동 생성하는 이 보안그룹은 기본적으로 자기 자신(클러스터
# 내부 통신)만 허용하고 ALB 등 외부는 전혀 안 열려있어서, ALB 헬스체크/트래픽이 전부
# Target.Timeout으로 막힘 - ECS 시절 ecs_sg의 ALB 인바운드 규칙과 동일한 역할을 여기서 해줌
resource "aws_security_group_rule" "alb_to_pods" {
  count                    = var.enable_eks ? 1 : 0
  type                     = "ingress"
  security_group_id        = aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id
  from_port                = var.container_port
  to_port                  = var.container_port
  protocol                 = "tcp"
  source_security_group_id = var.alb_security_group_id
  description              = "ALB health check/traffic to backend pods"
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

# kube-system은 이제 EC2 노드그룹(system)에서 돎 - Fargate Profile 없음(하이브리드 전환,
# ArgoCD/ALB Controller/CoreDNS/metrics-server를 Fargate 최소과금에서 빼내려는 목적)

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

# Fargate Profile이 API 상 ACTIVE가 돼도, 클러스터 내부의 fargate-scheduler 컴포넌트
# 자체가 리더 선출을 마치기까지 별도로 시간이 좀 걸림(실측 1~2분) - 예전엔 CoreDNS가 이
# 경합의 희생양이었는데, CoreDNS가 이제 EC2 노드그룹으로 옮겨가서 이 문제 자체가 없어짐.
# app(backend)만 여전히 Fargate라 이 profile용으로만 안전하게 남겨둠
resource "time_sleep" "fargate_scheduler_warmup" {
  count           = var.enable_eks ? 1 : 0
  depends_on      = [aws_eks_fargate_profile.app]
  create_duration = "2m"
}

# CoreDNS 애드온 - 이제 EC2 노드그룹에서 돎(Fargate가 아니라 진짜 노드라 fargate-scheduler
# 경합 자체가 없음 - 노드가 Ready면 바로 표준 스케줄러가 배치함)
resource "aws_eks_addon" "coredns" {
  count                       = var.enable_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "coredns"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}

# ===================== EC2 노드그룹(관리용 파드 전용) =====================
# vpc-cni/kube-proxy는 Fargate 전용이던 이 클러스터엔 지금까지 필요 없었음(Fargate는 AWS가
# IP 할당/Service 라우팅을 내부적으로 알아서 처리) - 근데 진짜 EC2 노드는 이 둘이 DaemonSet
# 형태로 노드마다 떠있어야 함(Fargate는 애초에 DaemonSet 자체를 못 돌림 - 그래서 이 두
# 애드온이 지금까지 아예 필요 없었던 것). aws_eks_node_group.system이 만들어져야(=DaemonSet이
# 스케줄될 실제 노드가 있어야) 의미가 있어서 그걸 기다림
resource "aws_eks_addon" "vpc_cni" {
  count                       = var.enable_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}

resource "aws_eks_addon" "kube_proxy" {
  count                       = var.enable_eks ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.system]
}

# 노드(EC2 인스턴스) 자체가 클러스터에 join할 때 assume하는 롤 - Fargate 파드 실행 롤이랑
# 완전히 별개 개념(그건 "파드가 뜰 때" 쓰는 롤, 이건 "노드 자체가 존재하려면" 필요한 롤)
resource "aws_iam_role" "node_group" {
  count = var.enable_eks ? 1 : 0
  name  = "${var.region_name}-eks-node-group-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_group_worker" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.node_group[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_group_cni" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.node_group[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_group_ecr" {
  count      = var.enable_eks ? 1 : 0
  role       = aws_iam_role.node_group[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ArgoCD/ALB Controller/CoreDNS/metrics-server처럼 "실사용량은 적은데 Fargate 최소과금
# 단위로 파드마다 따로 잡히는" 관리용 파드들을 여기 몰아넣는 전용 노드 - 이 9개 파드 실사용량
# 다 합쳐도 CPU 23m/메모리 362Mi 수준이라 t3.small(2vCPU/2GB) 하나로 충분히 여유 있음.
# 오토스케일러 없이 고정 크기로 단순하게(max=2는 노드 교체/업그레이드 시 잠깐 여유분용,
# 평소엔 desired=1대로만 운영)
resource "aws_eks_node_group" "system" {
  count           = var.enable_eks ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node_group[0].arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = ["t3.small"]

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_group_worker,
    aws_iam_role_policy_attachment.node_group_cni,
    aws_iam_role_policy_attachment.node_group_ecr,
  ]
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
  # var.backend_task_policy_arn는 root main.tf에서 module.backend_foundation.task_policy_arn을
  # 항상 넘겨받아서 이 스택 안에서는 실질적으로 절대 빈 문자열이 아님 - "빈 문자열이면 스킵"
  # 조건은 아직 존재하지 않는 리소스에서 나온 계산값을 plan 시점에 미리 판단하려는 거라
  # fresh 계정에서 "Invalid count argument"로 apply가 막히는 원인이었음. enable_eks만으로 게이팅
  count      = var.enable_eks ? 1 : 0
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

# Tavily API 키 - ECS는 실행 롤이 컨테이너 시작 시점에 SSM에서 직접 주입해줬지만 EKS엔 그
# 메커니즘이 없어서 k8s Secret으로 만들어 env로 연결함. backend_foundation이 SSM에 쓴 값을
# 같은 apply 안에서 data source로 도로 읽는 방식은 "방금 만든 리소스를 즉시 되읽기" 패턴이라
# 리소스 생성 순서가 꼬여서 "couldn't find resource" 에러가 났음(SSM 쓰기가 끝나기 전에 읽기가
# 먼저 평가됨) - 그래서 원본 변수값을 그대로 넘겨받아 씀(SSM 왕복 없이)
resource "kubernetes_secret_v1" "backend" {
  count = var.enable_eks && var.tavily_api_key != "" ? 1 : 0
  metadata {
    name      = "backend-secrets"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }
  data = {
    TAVILY_API_KEY = var.tavily_api_key
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
    { name = "PROMETHEUS_REMOTE_WRITE_URL", value = var.prometheus_remote_write_url },
  ] : []

}

# backend Deployment/Service/HPA/PDB는 ArgoCD(k8s/backend/, git 관리)로 이관함 - 코드
# 배포마다 바뀌는 워크로드 정의라서 GitOps로 넘기고, 이 값들(다른 모듈 output 의존이라
# Terraform이 계산해야 하는 것들)만 ConfigMap으로 만들어 Deployment가 envFrom으로 참조하게 함.
# ADOT 사이드카 컨테이너 자체는 k8s/backend/deployment.yaml에 직접 정의돼 있음 - 이 ConfigMap의
# PROMETHEUS_REMOTE_WRITE_URL/AWS_REGION 값을 envFrom으로 받아 remote-write 대상을 결정함
resource "kubernetes_config_map_v1" "backend_env" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name      = "backend-env"
    namespace = kubernetes_namespace_v1.app[0].metadata[0].name
  }
  data = { for e in local.env_vars : e.name => e.value }
}

# backend Service(ClusterIP)는 이제 k8s/backend/service.yaml(git, ArgoCD 관리) 소유 -
# 이름("backend")은 안 바뀌는 리터럴이라 아래 TargetGroupBinding에서 문자열로 직접 참조

# AWS Load Balancer Controller가 제공하는 CRD - backend Service(git 관리) 뒤 파드 IP들을
# 기존 ALB 대상 그룹(target_type=ip)에 직접 등록해줌. 신규 클러스터에서는
# helm_release.aws_load_balancer_controller가 CRD를 먼저 설치해야 이 리소스가 plan/apply될
# 수 있어서, 최초 1회는 2단계 apply가 필요함(README/PR 설명에 명시 - Grafana IAM Identity
# Center 사전조건과 같은 성격의 제약)
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
        name = "backend"
        port = var.container_port
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}

# EKS Fargate는 ECS와 달리 파드 로그가 자동으로 CloudWatch에 안 감 - kube-system의
# aws-logging ConfigMap으로 Fluent Bit 라우팅을 명시해야 함(Fargate 로깅의 표준 방식).
# kube-system 자체는 이제 EC2 노드로 옮겨갔지만, 이 ConfigMap은 여전히 "클러스터 전체
# Fargate 파드"(=지금은 app/backend만)의 로그 라우팅을 담당하는 전역 설정이라 계속 필요함
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

  depends_on = [aws_eks_fargate_profile.app]
}

# backend HPA/PDB도 k8s/backend/(git, ArgoCD 관리)로 이관됨 - metrics-server는 여전히
# 여기서 설치(HPA가 어느 쪽에서 관리되든 클러스터 차원의 전제조건이라 인프라 레이어에 남김)

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
  # ALB Controller는 이제 EC2 노드그룹에서 돎(Fargate 아님)
  depends_on = [aws_eks_node_group.system]
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

  # Fargate의 가상 kubelet이 내주는 인증서가 127.0.0.1용으로만 발급돼서(실제 파드/노드 IP가
  # SAN에 없음) metrics-server 기본 설정(엄격한 TLS 검증)으로는 "x509: certificate is valid
  # for 127.0.0.1, not <실제 IP>"로 모든 스크레이핑이 실패함 - EKS Fargate에서 잘 알려진
  # 제약이라 AWS/metrics-server 문서에도 명시된 표준 우회법(kubelet TLS 검증만 건너뜀,
  # 메트릭 데이터 자체의 신뢰성과는 무관 - 같은 클러스터 내부 스크레이핑이라 위험 낮음)
  #
  # 그래도 metrics-server가 "자기 자신이 떠있는 노드"만 계속 403으로 실패함(다른 노드는
  # 정상 스크레이핑됨, 실제로 확인함) - Fargate가 표준 kubelet 포트(10250)를 내부적으로
  # 특별 취급해서 metrics-server 자신이 그 포트로 서빙하는 것과 충돌하는 것으로 보임.
  # AWS 공식 트러블슈팅 가이드(repost.aws/knowledge-center/eks-metrics-server-install-troubleshoot)
  # 권장대로 서빙 포트를 10250 대신 10251로 바꿔서 이 충돌을 피함 - 다른 노드를 긁어올 때
  # 쓰는 kubelet 포트(10250, 고정값)는 안 바뀜, metrics-server 자신의 서빙 포트만 바뀜
  set = [
    { name = "args[0]", value = "--kubelet-insecure-tls" },
    { name = "args[1]", value = "--secure-port=10251" },
    { name = "containerPort", value = "10251" }
  ]

  # metrics-server는 이제 EC2 노드그룹에서 돎 - 근데 backend(app)는 여전히 Fargate라
  # --kubelet-insecure-tls는 계속 필요함(Fargate 파드 스크레이핑용). 포트 변경(10251)도
  # 굳이 원복 안 함 - 부작용 없고, 나중에 또 자기 노드 스크레이핑 이슈가 재발해도 이미 대비됨
  depends_on = [aws_eks_node_group.system]
}

# ===================== ArgoCD (GitOps - backend 배포 전용) =====================
# argocd 네임스페이스도 EC2 노드그룹(system)에서 돎 - Fargate Profile 없음(위 kube-system과
# 동일한 이유)

resource "kubernetes_namespace_v1" "argocd" {
  count = var.enable_eks ? 1 : 0
  metadata {
    name = "argocd"
  }
  depends_on = [aws_eks_access_entry.admin, aws_eks_access_policy_association.admin]
}

# UI/API는 새 ALB 리스너나 자체 ELB를 만들지 않고 port-forward로만 접근(운영툴이라 공개
# 노출 불필요 - 새 상시 비용도 안 만듦). 레포(ahowme12/Dambda)가 public이라
# ArgoCD가 clone할 때 별도 자격증명이 필요 없음(repo-creds Secret 불필요)
resource "helm_release" "argocd" {
  count      = var.enable_eks ? 1 : 0
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd[0].metadata[0].name

  # Fargate는 파드 하나하나가 각자 독립 과금되는 VM이라(EC2 노드처럼 여러 파드를 한 노드에
  # 얹어 나눠 쓰는 구조가 아님), ArgoCD 기본 설치가 띄우는 7개 컴포넌트 전부가 그대로
  # 월 비용으로 잡힘 - 이 중 3개(dex/applicationSet/notifications)는 지금 안 쓰는 기능이라
  # (SSO 로그인, 다중 Application 템플릿, ArgoCD 자체 알림 연동 - 전부 미사용) 꺼서
  # 7개 → 4개로 줄임(application-controller/redis/repo-server/server만 유지)
  set = [
    { name = "server.service.type", value = "ClusterIP" },
    { name = "dex.enabled", value = "false" },
    { name = "notifications.enabled", value = "false" },
    # 최신 argo-helm 차트엔 applicationSet 전용 enabled 플래그가 없어서(dex/notifications와
    # 달리 "코어" 컴포넌트로 취급됨) replicas=0으로 사실상 꺼둠 - 어차피 ApplicationSet
    # 리소스 자체를 하나도 안 써서(Application CRD 하나만 직접 관리) 기능상 영향 없음
    { name = "applicationSet.replicas", value = "0" },
  ]

  # ArgoCD는 이제 EC2 노드그룹에서 돎(Fargate 아님)
  depends_on = [aws_eks_node_group.system]
}

# backend 워크로드(Deployment/Service/HPA/PDB, k8s/backend/)의 GitOps 진입점 - Terraform은
# 이 Application 하나만 소유하고, 그 안 실제 리소스들은 ArgoCD가 git과 동기화함.
# TargetGroupBinding과 동일하게 이 레포에 이미 있는 kubernetes_manifest(CRD) 관례를 따름
resource "kubernetes_manifest" "argocd_application_backend" {
  count = var.enable_eks ? 1 : 0
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "backend"
      namespace = kubernetes_namespace_v1.argocd[0].metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/ahowme12/Dambda.git"
        targetRevision = "main"
        path           = "k8s/backend"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace_v1.app[0].metadata[0].name
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
