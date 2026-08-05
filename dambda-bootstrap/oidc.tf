data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # dambda 모듈이 만드는 리소스 이름은 전부 이 접두사로 시작함 (region_name / us_region_name)
  # -> "my-app-dev-*"가 서울(my-app-dev-*)과 us-east-1(my-app-dev-us-*) 둘 다 커버함
  app_name_prefix = "my-app-dev"
}

# 1. GitHub OIDC Provider 등록
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
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
        Resource = ["arn:aws:iam::${local.account_id}:role/${local.app_name_prefix}-*"]
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
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketWebsite",
          "s3:PutBucketWebsite",
          "s3:DeleteBucketWebsite",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:DeleteBucketPublicAccessBlock",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketNotification",
          "s3:PutBucketNotification",
          "s3:GetBucketAcl",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
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
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:UpdateContinuousBackups",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
          # Global Table replica 생성 과정에서 AWS가 내부적으로 씀 (관리 API지만 Scan 필요)
          "dynamodb:Scan"
        ]
        Resource = [
          "arn:aws:dynamodb:ap-northeast-2:${local.account_id}:table/${local.app_name_prefix}-*",
          "arn:aws:dynamodb:us-east-1:${local.account_id}:table/${local.app_name_prefix}-*"
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
          "arn:aws:logs:*:${local.account_id}:log-group:/ecs/${local.app_name_prefix}*",
          "arn:aws:logs:*:${local.account_id}:log-group:/ecs/${local.app_name_prefix}*:*"
        ]
      },
      {
        # DescribeLogGroups는 "목록 조회" 액션이라 AWS가 리소스 단위 스코프 자체를 지원 안 함
        Sid      = "CloudWatchLogsDescribe"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
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
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:AttachInternetGateway", "ec2:DetachInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:ReplaceRoute",
          "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable", "ec2:DescribeRouteTables",
          "ec2:AllocateAddress", "ec2:ReleaseAddress", "ec2:DescribeAddresses", "ec2:DescribeAddressesAttribute",
          "ec2:CreateNatGateway", "ec2:DeleteNatGateway", "ec2:DescribeNatGateways",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress", "ec2:RevokeSecurityGroupEgress",
          "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
          "ec2:CreateVpcEndpoint", "ec2:DeleteVpcEndpoints", "ec2:DescribeVpcEndpoints", "ec2:ModifyVpcEndpoint", "ec2:DescribePrefixLists",
          "ec2:CreateVpcPeeringConnection", "ec2:AcceptVpcPeeringConnection", "ec2:DeleteVpcPeeringConnection", "ec2:DescribeVpcPeeringConnections",
          "ec2:CreateTags", "ec2:DeleteTags", "ec2:DescribeTags",
          "ec2:DescribeAvailabilityZones"
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
          "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DescribeLoadBalancers", "elasticloadbalancing:DescribeLoadBalancerAttributes", "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeTargetGroupAttributes", "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:CreateListener", "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DescribeListeners", "elasticloadbalancing:ModifyListener", "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags", "elasticloadbalancing:DescribeTags"
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
          "application-autoscaling:RegisterScalableTarget",
          "application-autoscaling:DeregisterScalableTarget",
          "application-autoscaling:DescribeScalableTargets",
          "application-autoscaling:PutScalingPolicy",
          "application-autoscaling:DeleteScalingPolicy",
          "application-autoscaling:DescribeScalingPolicies"
        ]
        Resource = "*"
      },
      {
        # translation/moderation/cognito post_confirmation Lambda (서울에만 존재)
        Sid    = "LambdaFunctions"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:GetFunction", "lambda:GetFunctionConfiguration",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration", "lambda:DeleteFunction",
          "lambda:TagResource", "lambda:ListTags", "lambda:ListVersionsByFunction",
          "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
          "lambda:CreateEventSourceMapping", "lambda:GetEventSourceMapping",
          "lambda:UpdateEventSourceMapping", "lambda:DeleteEventSourceMapping", "lambda:ListEventSourceMappings",
          "lambda:GetFunctionCodeSigningConfig"
        ]
        Resource = ["arn:aws:lambda:ap-northeast-2:${local.account_id}:function:${local.app_name_prefix}-*"]
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
          "ecr:CreateRepository", "ecr:DeleteRepository", "ecr:DescribeRepositories",
          "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy", "ecr:TagResource", "ecr:ListTagsForResource",
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"
        ]
        Resource = ["arn:aws:ecr:ap-northeast-2:${local.account_id}:repository/${local.app_name_prefix}-*"]
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
        # cognito 모듈 (서울 단일 리전). CreateUserPool은 풀 ID가 생성 전에 없어 "*" 필요,
        # 계정에 이 풀 하나만 존재하므로 리전 제한으로 사실상 범위가 동일함
        Sid    = "CognitoUserPool"
        Effect = "Allow"
        Action = [
          "cognito-idp:CreateUserPool", "cognito-idp:DeleteUserPool", "cognito-idp:DescribeUserPool", "cognito-idp:UpdateUserPool",
          "cognito-idp:CreateUserPoolClient", "cognito-idp:DeleteUserPoolClient", "cognito-idp:DescribeUserPoolClient", "cognito-idp:UpdateUserPoolClient",
          "cognito-idp:CreateGroup", "cognito-idp:DeleteGroup", "cognito-idp:GetGroup", "cognito-idp:UpdateGroup",
          "cognito-idp:TagResource", "cognito-idp:ListTagsForResource"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = ["ap-northeast-2"]
          }
        }
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
