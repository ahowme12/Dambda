data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # dambda 모듈이 만드는 리소스 이름은 전부 이 접두사로 시작함 (region_name / us_region_name)
  # -> "my-app-dev-*"가 서울(my-app-dev-*)과 us-east-1(my-app-dev-us-*) 둘 다 커버함
  app_name_prefix = "my-app-dev"
}

# 1. GitHub OIDC Provider 등록
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}

# 2. GitHub Actions가 사용할 IAM Role
resource "aws_iam_role" "github_actions_role" {
  name = "github-actions-role"


  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:ahowme12@80324068/github-actions-test@1308447274:ref:refs/heads/main",
            "repo:ahowme12@80324068/github-actions-test@1308447274:pull_request"
          ]
        }
      }
    }]
  })
}

# ===================== 3-1. core: state 접근 + IAM 관리 =====================
resource "aws_iam_policy" "core" {
  name        = "github-actions-policy-core"
  description = "Terraform state access + IAM management for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "TerraformStateAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = [
          "arn:aws:s3:::dambda-bootstrap-bucket",
          "arn:aws:s3:::dambda-bootstrap-bucket/*",
          "arn:aws:dynamodb:ap-northeast-2:${local.account_id}:table/terraform-lock-table"
        ]
      },
      {
        # dambda 모듈들이 만드는 role만 대상. github-actions-role 자신은 이 패턴에
        # 안 걸려서 자기 권한 상승이 불가능함 (핵심 방어선).
        Sid    = "IamRoleManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:GetRole",
          "iam:DeleteRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
          "iam:GetRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole"
        ]
        Resource = [
          "arn:aws:iam::${local.account_id}:role/${local.app_name_prefix}-*"
        ]
      },
      {
        # compute 모듈의 ecs_task_policy처럼 role이 아닌 별도 관리형 정책 리소스
        Sid    = "IamPolicyManagement"
        Effect = "Allow"
        Action = [
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:ListPolicyVersions"
        ]
        Resource = ["arn:aws:iam::${local.account_id}:policy/${local.app_name_prefix}-*"]
      },
      {
        Sid    = "DenySelfModification"
        Effect = "Deny"
        Action = [
          "iam:UpdateAssumeRolePolicy",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy"
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/github-actions-role"
      },
      {
        # compute 모듈의 오토스케일링이 최초 사용 시 AWS가 자동 생성하는 서비스연결역할
        Sid      = "IamServiceLinkedRoleForAutoscaling"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${local.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "ecs.application-autoscaling.amazonaws.com"
          }
        }
      },
      {
        # dynamodb 모듈의 Global Table replica가 최초 사용 시 AWS가 자동 생성하는 서비스연결역할
        Sid      = "IamServiceLinkedRoleForDynamoDbReplication"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${local.account_id}:role/aws-service-role/replication.dynamodb.amazonaws.com/AWSServiceRoleForDynamoDBReplication"]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "replication.dynamodb.amazonaws.com"
          }
        }
      },
      {
        # aws_ecr_replication_configuration이 최초 활성화 시 AWS가 자동 생성하는 서비스연결역할
        Sid      = "IamServiceLinkedRoleForEcrReplication"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${local.account_id}:role/aws-service-role/replication.ecr.amazonaws.com/AWSServiceRoleForECRReplication"]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "replication.ecr.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ===================== 3-2. data: S3 / DynamoDB / CloudWatch Logs =====================
resource "aws_iam_policy" "data" {
  name        = "github-actions-policy-data"
  description = "S3 app buckets + DynamoDB app tables + CloudWatch Logs for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # storage 모듈: static_site / uploads 버킷 (서울 + us-east-1)
        Sid    = "S3AppBuckets"
        Effect = "Allow"
        Action = [
          # 조회(Get/List)는 뭘 바꾸거나 지울 수 없어서 통째로 허용 - Terraform이
          # 리소스 생성 후 상태를 채우려고 온갖 하위 속성을 조회하는데 매번 하나씩
          # 빠진 걸 찾느니 읽기 전체를 허용하는 게 실용적
          "s3:Get*",
          "s3:List*",
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucket*",
          "s3:DeleteBucket*",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketWebsite",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = [
          "arn:aws:s3:::${local.app_name_prefix}-*",
          "arn:aws:s3:::${local.app_name_prefix}-*/*"
        ]
      },
      {
        # dynamodb 모듈: users/content/translations Global Table (서울 홈 + us-east-1 replica)
        Sid    = "DynamoDbAppTables"
        Effect = "Allow"
        Action = [
          # Global Table replica 생성 과정에서 AWS가 내부적으로 Query/Scan 등을 씀 -
          # 정확히 어떤 조회 액션이 필요한지 문서화가 안 돼 있어서 조회 계열 통째로 허용
          "dynamodb:Describe*",
          "dynamodb:List*",
          "dynamodb:Get*",
          "dynamodb:Query",
          "dynamodb:Scan",
          # Global Table replica 생성 과정이 실제 아이템 쓰기/읽기까지 수반함
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:UpdateTable",
          # Global Table replica는 CreateTable/UpdateTable과 별개의 전용 액션이 있음
          "dynamodb:CreateTableReplica",
          "dynamodb:DeleteTableReplica",
          "dynamodb:UpdateTableReplicaAutoScaling",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:TagResource",
          "dynamodb:UntagResource"
        ]
        Resource = [
          "arn:aws:dynamodb:*:${local.account_id}:table/${local.app_name_prefix}-*",
        ]
      },
      {
        # compute 모듈: /ecs/<region_name>-logs 로그 그룹 (서울 + us-east-1)
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:logs:*:${local.account_id}:log-group:/ecs/*"
        ]
      },
      {
        # DescribeLogGroups는 "목록 조회" 액션이라 AWS가 리소스 단위 스코프 자체를 지원 안 함
        Sid      = "CloudWatchLogsDescribe"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        # storage 모듈: 정적 사이트 HTTPS용 CloudFront + OAC. CloudFront는 리전 개념이
        # 없는 글로벌 리소스라 이름/리전 기반 스코프가 불가능함(ID는 생성 후에만 알 수 있음)
        Sid    = "CloudFrontStaticSite"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution", "cloudfront:UpdateDistribution", "cloudfront:DeleteDistribution",
          "cloudfront:GetDistribution", "cloudfront:ListDistributions", "cloudfront:TagResource", "cloudfront:ListTagsForResource",
          "cloudfront:CreateOriginAccessControl", "cloudfront:UpdateOriginAccessControl", "cloudfront:DeleteOriginAccessControl",
          "cloudfront:GetOriginAccessControl", "cloudfront:ListOriginAccessControls",
          "cloudfront:CreateInvalidation", "cloudfront:GetInvalidation", "cloudfront:ListInvalidations"
        ]
        Resource = "*"
      }
    ]
  })
}

# ===================== 3-3. network: EC2/VPC + ELB =====================
resource "aws_iam_policy" "network" {
  name        = "github-actions-policy-network"
  description = "VPC networking + load balancer for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # network 모듈: VPC/서브넷/IGW/NAT/라우팅/보안그룹/VPC엔드포인트/피어링
        # EC2는 생성 시점 리소스 단위 권한을 지원하지 않는 액션이 대부분이라
        # Resource="*"가 AWS 문서상 정상 형태. 대신 리전을 서울/us-east-1로 제한.
        Sid    = "Ec2Networking"
        Effect = "Allow"
        Action = [
          # 조회(Describe)는 통째로 허용 - EC2는 특히 하위 속성 조회 액션이 많아서
          # 하나씩 나열하면 끝이 없음. Resource="*" + 리전 조건은 아래 그대로 유지.
          "ec2:Describe*",
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:ModifyVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DisassociateAddress",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:ModifyVpcEndpoint",
          "ec2:CreateVpcPeeringConnection", "ec2:AcceptVpcPeeringConnection", "ec2:DeleteVpcPeeringConnection",
          "ec2:CreateTags", "ec2:DeleteTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = ["ap-northeast-2", "us-east-1"]
          }
        }
      },
      {
        # alb 모듈. ELBv2도 생성 액션 대부분 리소스 단위 스코프 미지원 -> "*" + 리전 제한
        Sid    = "LoadBalancing"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:Describe*",
          "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer", "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = ["ap-northeast-2", "us-east-1"]
          }
        }
      }
    ]
  })
}

# ===================== 3-4. compute: ECS / Auto Scaling / Lambda / API Gateway / Cognito =====================
resource "aws_iam_policy" "compute" {
  name        = "github-actions-policy-compute"
  description = "ECS, autoscaling, Lambda, API Gateway, Cognito for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # compute 모듈: 클러스터/서비스는 이름 기반 스코프 가능
        Sid    = "EcsClusterAndService"
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster", "ecs:DeleteCluster", "ecs:DescribeClusters",
          "ecs:CreateService", "ecs:UpdateService", "ecs:DeleteService", "ecs:DescribeServices",
          "ecs:TagResource", "ecs:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:ecs:*:${local.account_id}:cluster/${local.app_name_prefix}-*",
          "arn:aws:ecs:*:${local.account_id}:service/${local.app_name_prefix}-*/*"
        ]
      },
      {
        # task definition은 AWS 문서상 리소스 단위 스코프 미지원 액션들이라 "*" 필요
        Sid    = "EcsTaskDefinition"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions"
        ]
        Resource = "*"
      },
      {
        # 오토스케일링 자체도 리소스 단위 스코프 미지원
        Sid    = "ApplicationAutoScaling"
        Effect = "Allow"
        Action = [
          "application-autoscaling:Describe*",
          "application-autoscaling:ListTagsForResource",
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DeregisterScalableTarget",
          "application-autoscaling:PutScalingPolicy",
          "application-autoscaling:DeleteScalingPolicy",
          "application-autoscaling:TagResource"
        ]
        Resource = "*"
      },
      {
        # translation/moderation/cognito post_confirmation Lambda (서울에만 존재)
        Sid    = "LambdaFunctions"
        Effect = "Allow"
        Action = [
          "lambda:Get*",
          "lambda:List*",
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:DeleteFunction",
          "lambda:TagResource",
          "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:CreateEventSourceMapping",
          "lambda:UpdateEventSourceMapping", "lambda:DeleteEventSourceMapping"
        ]
        Resource = [
          "arn:aws:lambda:ap-northeast-2:${local.account_id}:function:${local.app_name_prefix}-*",
          # event source mapping은 function과 별개 ARN 타입이고 ID가 생성 시점에 랜덤 부여돼
          # 이름 기반 스코프가 불가능함 - 계정+리전으로만 제한
          "arn:aws:lambda:ap-northeast-2:${local.account_id}:event-source-mapping:*"
        ]
      },
      {
        # api_gateway 모듈. HTTP API는 REST 동사(GET/POST/...) 기반 권한 모델이라
        # 액션 자체를 세분화할 수 없고, 대신 관리 대상 경로로 Resource를 좁힘
        Sid    = "ApiGatewayManagement"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = [
          "arn:aws:apigateway:*::/apis",
          "arn:aws:apigateway:*::/apis/*",
          "arn:aws:apigateway:*::/vpclinks",
          "arn:aws:apigateway:*::/vpclinks/*",
          "arn:aws:apigateway:*::/tags/*"
        ]
      },
      {
        # backend/(Express) 이미지 저장소. Docker 레이어 push까지 포함해서 repository ARN으로 스코프
        Sid    = "EcrBackendRepository"
        Effect = "Allow"
        Action = [
          "ecr:Describe*",
          "ecr:List*",
          "ecr:Get*",
          "ecr:CreateRepository", "ecr:DeleteRepository",
          "ecr:PutLifecyclePolicy", "ecr:DeleteLifecyclePolicy", "ecr:TagResource",
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:ap-northeast-2:${local.account_id}:repository/${local.app_name_prefix}-*",
          "arn:aws:ecr:us-east-1:${local.account_id}:repository/${local.app_name_prefix}-*"
        ]
      },
      {
        # docker login 시 계정 단위로 인증 토큰을 받는 액션이라 리소스 단위 스코프 자체를
        # 지원 안 함 (Resource="*" 아니면 AWS가 이 액션을 아예 허용 안 함)
        Sid      = "EcrAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # ECR 네이티브 리플리케이션(서울->us-east-1 자동 이미지 복제) 설정. 레지스트리
        # 단위(계정 전체) 설정이라 리소스 단위 스코프 자체를 지원 안 함
        Sid      = "EcrReplicationConfig"
        Effect   = "Allow"
        Action   = ["ecr:PutReplicationConfiguration", "ecr:DescribeRegistry"]
        Resource = "*"
      },
      {
        # compute 모듈: Tavily API 키(SecureString) 파라미터 관리. Terraform이 apply 후
        # 상태를 읽어올 때는 GetParameter(단수), ECS가 컨테이너 시작 시 값을 주입할 때는
        # GetParameters(복수) - 액션 이름이 비슷해도 서로 다른 액션이라 둘 다 필요
        Sid    = "SsmTavilyApiKey"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter", "ssm:DeleteParameter",
          "ssm:GetParameter", "ssm:GetParameters",
          "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource", "ssm:ListTagsForResource"
        ]
        Resource = ["arn:aws:ssm:*:${local.account_id}:parameter/${local.app_name_prefix}/*"]
      },
      {
        # DescribeParameters는 "목록 조회" 액션이라 AWS가 리소스 단위 스코프 자체를 지원 안 함
        # (logs:DescribeLogGroups와 동일한 이유) - Terraform이 apply 후 drift 확인 시 호출함
        Sid      = "SsmDescribeParameters"
        Effect   = "Allow"
        Action   = ["ssm:DescribeParameters"]
        Resource = "*"
      },
      {
        # cognito 모듈 (서울 단일 리전). CreateUserPool은 풀 ID가 생성 전에 없어 "*" 필요,
        # 계정에 이 풀 하나만 존재하므로 리전 제한으로 사실상 범위가 동일함
        Sid    = "CognitoUserPool"
        Effect = "Allow"
        Action = [
          "cognito-idp:Describe*",
          "cognito-idp:Get*",
          "cognito-idp:List*",
          "cognito-idp:CreateUserPool", "cognito-idp:DeleteUserPool", "cognito-idp:UpdateUserPool",
          "cognito-idp:CreateUserPoolClient", "cognito-idp:DeleteUserPoolClient", "cognito-idp:UpdateUserPoolClient",
          "cognito-idp:CreateGroup", "cognito-idp:DeleteGroup", "cognito-idp:UpdateGroup",
          "cognito-idp:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = ["ap-northeast-2"]

          }
        }
      },
      {
        # 이건 sqs 권한
        Sid    = "SqsManagement"
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:DeleteQueue",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:ListQueueTags",
          "sqs:TagQueue",
          "sqs:UntagQueue"
        ]
        Resource = [
          "arn:aws:sqs:*:${local.account_id}:${local.app_name_prefix}-*"
        ]
      },
      {
        # sns:GetTopic은 실존하지 않는 액션이라 뺐음(실제 조회 액션은 GetTopicAttributes) -
        # aws_sns_topic_subscription이 상태를 읽어올 때 GetSubscriptionAttributes/
        # ListSubscriptionsByTopic도 필요함(특히 email 프로토콜은 구독 후 계속
        # PendingConfirmation 상태라 refresh 때마다 다시 조회됨)
        Sid    = "SnsManagement"
        Effect = "Allow"
        Action = [
          "sns:GetTopicAttributes",
          "sns:ListTagsForResource",
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:Publish",
          "sns:TagResource",
          "sns:UntagResource"
        ]
        Resource = [
          "arn:aws:sns:*:${local.account_id}:${local.app_name_prefix}-*"
        ]
      },
      {
        Sid    = "EventBridgePipesManagement"
        Effect = "Allow"
        Action = [
          "pipes:CreatePipe",
          "pipes:UpdatePipe",
          "pipes:DeletePipe",
          "pipes:DescribePipe",
          "pipes:ListPipes",
          "pipes:StartPipe",
          "pipes:StopPipe",
          "pipes:TagResource",
          "pipes:UntagResource",
          "pipes:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:pipes:*:${local.account_id}:pipe/${local.app_name_prefix}-*"
        ]
      },
      {
        Sid    = "StepFunctionsManagement"
        Effect = "Allow"
        Action = [
          "states:ListStateMachineVersions",
          "states:CreateStateMachine",
          "states:DeleteStateMachine",
          "states:UpdateStateMachine",
          "states:DescribeStateMachine",
          "states:ListStateMachines",
          "states:ValidateStateMachineDefinition",
          "states:TagResource",
          "states:UntagResource",
          "states:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:states:*:${local.account_id}:stateMachine:${local.app_name_prefix}-*",
          # ValidateStateMachineDefinition API는 생성 전 검증용이라 wildcard(*) 지정이 필요한 경우가 많습니다.
          "arn:aws:states:*:${local.account_id}:stateMachine:*"
        ]
      },
      {
        # modules/grafana. CreateWorkspace는 워크스페이스 ID가 생성 전이라 리소스 단위
        # 스코프 불가 -> "*". 나머지(서비스 계정/토큰/역할 부여 등)는 계정 내 워크스페이스가
        # 하나뿐이라 실용적으로 크게 문제 없이 와일드카드로 묶음
        Sid    = "GrafanaManagement"
        Effect = "Allow"
        Action = [
          "grafana:CreateWorkspace",
          "grafana:DeleteWorkspace",
          "grafana:DescribeWorkspace",
          "grafana:UpdateWorkspace",
          "grafana:UpdateWorkspaceConfiguration",
          "grafana:TagResource",
          "grafana:UntagResource",
          "grafana:ListTagsForResource",
          "grafana:CreateWorkspaceServiceAccount",
          "grafana:DeleteWorkspaceServiceAccount",
          "grafana:ListWorkspaceServiceAccounts",
          "grafana:CreateWorkspaceServiceAccountToken",
          "grafana:DeleteWorkspaceServiceAccountToken",
          "grafana:ListWorkspaceServiceAccountTokens",
          "grafana:UpdatePermissions",
          "grafana:DescribePermissions"
        ]
        Resource = "*"
      },
      {
        # AMG가 authentication_providers=AWS_SSO로 워크스페이스를 만들/관리할 때 내부적으로
        # Identity Center 쪽 연동 상태를 조회하려고 호출함(CreateWorkspace 자체가 이걸 씀,
        # 사람이 직접 부르는 액션이 아님) - 전부 계정 단위 조회라 리소스 스코프 미지원
        Sid    = "GrafanaSsoIntegration"
        Effect = "Allow"
        Action = [
          "sso:DescribeRegisteredRegions",
          "sso:GetSharedSsoConfiguration",
          "sso:ListDirectoryAssociations",
          "sso:GetManagedApplicationInstance",
          # 워크스페이스를 처음 만들 때 Grafana를 Identity Center의 관리형 애플리케이션으로
          # 등록하는 단계 - instance ARN + applicationProvider/grafana ARN 둘 다 걸리는데,
          # instance ARN은 Identity Center를 켤 때마다 새로 생기는 계정별 랜덤 ID라
          # 하드코딩 안 하고 "*"로 둠(다른 sso:* 액션들과 동일한 이유)
          "sso:CreateManagedApplicationInstance",
          "sso:ListProfiles",
          "sso:GetProfile",
          "sso:ListProfileAssociations",
          "sso-directory:DescribeUser",
          "sso-directory:DescribeGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

# 4. 정책들을 role에 부착
resource "aws_iam_role_policy_attachment" "core" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.core.arn
}

resource "aws_iam_role_policy_attachment" "data" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.data.arn
}

resource "aws_iam_role_policy_attachment" "network" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.network.arn
}

resource "aws_iam_role_policy_attachment" "compute" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.compute.arn
}

# AMG를 IAM Identity Center(AWS_SSO) 인증으로 "처음" 만들 때 필요한 권한 조합을 AWS가
# 공식적으로 문서화해둠(직접 정의한 좁은 GrafanaSsoIntegration statement로는 sso: 액션이
# 하나씩 계속 더 나와서 왕복이 길어짐) - 이 3개 관리형 정책을 그대로 부착해서 한 번에 해결.
# 셋 다 AWS 관리형이라 이 프로젝트 정책처럼 6144자 제한 대상이 아님
resource "aws_iam_role_policy_attachment" "grafana_account_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSGrafanaAccountAdministrator"
}

resource "aws_iam_role_policy_attachment" "sso_member_account_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSSOMemberAccountAdministrator"
}

resource "aws_iam_role_policy_attachment" "sso_directory_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSSODirectoryAdministrator"
}