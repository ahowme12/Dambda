data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  # dambda 모듈이 만드는 리소스 이름은 전부 이 접두사로 시작함 (region_name / us_region_name)
  # -> "my-app-dev-*"가 서울(my-app-dev-*)과 us-east-1(my-app-dev-us-*) 둘 다 커버함
  app_name_prefix = "my-app-dev"
  # 수동 등록한 도메인의 Route53 존 ID (dambda.shop, auokay.cloud에서 이전) - 이 값만 바꾸면
  # 다른 도메인/계정으로 재사용 가능. 다른 계정이면 aws route53 list-hosted-zones로 새로 조회해서 넣을 것
  route53_zone_id = "Z100240729K1ZXP96PB7K"
  # 마이그레이션 중 옛 zone(auokay.cloud) 정리용 - 완전히 정리되면 이 local과
  # Route53ZoneRecordManagement의 두 번째 Resource 항목을 같이 지울 것
  old_route53_zone_id = "Z0464601LVH5LN44QO5G"
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
      # TODO: 다른 GitHub 계정/레포로 옮기면 이 owner/repo 부분을 새 값으로 바꾸고
      # apply해야 함 - 안 바꾸면 새 레포의 워크플로우가 sts:AssumeRoleWithWebIdentity에서
      # 막힘(이 sub 패턴에 안 걸려서). 코드 전체에서 계정/레포 이름이 하드코딩된 유일한 곳
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
          "iam:ListInstanceProfilesForRole",
          "iam:PassRole",
          # provider default_tags로 모든 리소스에 project=dambda 태그가 붙게 되면서
          # IAM Role도 태그 대상이 됨 - Tag/Untag가 없으면 role 관련 apply가 전부 실패함
          "iam:TagRole",
          "iam:UntagRole",
          "iam:ListRoleTags"
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
          "iam:ListPolicyVersions",
          "iam:TagPolicy",
          "iam:UntagPolicy"
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
      },
      {
        # aws_guardduty_detector가 최초 생성 시 AWS가 자동 생성하는 서비스연결역할
        Sid      = "IamServiceLinkedRoleForGuardDuty"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${local.account_id}:role/aws-service-role/guardduty.amazonaws.com/AWSServiceRoleForAmazonGuardDuty"]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "guardduty.amazonaws.com"
          }
        }
      },
      {
        # aws_chatbot_slack_channel_configuration이 최초 생성 시 AWS가 자동 생성하는 서비스연결역할
        Sid      = "IamServiceLinkedRoleForChatbot"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = ["arn:aws:iam::${local.account_id}:role/aws-service-role/management.chatbot.amazonaws.com/AWSServiceRoleForAWSChatbot"]
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "management.chatbot.amazonaws.com"
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
        # seed-products 워크플로우가 계정 ID가 붙은 실제 버킷 이름을 조회하려고 씀.
        # 계정 전체 버킷 목록 조회라 리소스 단위 스코프를 지원 안 해서 "*"
        Sid      = "S3ListAllBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets"]
        Resource = "*"
      },
      {
        # seed-products 워크플로우의 seed-products.js가 상품을 4개 언어로 번역함 - 이제
        # backend/src/services/translate.js가 AWS Translate 대신 Bedrock을 쓰므로
        # (compute 모듈의 ecs_task_policy와 동일한 이유) translate/comprehend가 아니라
        # bedrock:InvokeModel이 필요함. CI 자신의 role이라 ECS 태스크 role과 별개로 필요
        Sid      = "BedrockForSeeding"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "*"
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
        # backend_foundation 모듈: /eks/<region_name>-logs 로그 그룹 (ECS -> EKS 전환 전에는
        # /ecs/*였음 - 코드 전체에 더 이상 /ecs/* 로그 그룹이 없어서 이름만 바꿈, 추가 아님)
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:ListTagsForResource"
        ]
        # ":*" 접미사 버전도 같이 필요함(태그 관련 액션의 CloudWatch Logs ARN 매칭 특이사항 -
        # EksClusterLogGroup statement 주석 참고, 같은 이유로 여기도 선제적으로 추가)
        Resource = [
          "arn:aws:logs:*:${local.account_id}:log-group:/eks/*",
          "arn:aws:logs:*:${local.account_id}:log-group:/eks/*:*"
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
        Sid    = "AcmCertificateManagement"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:ListTagsForCertificate"
        ]
        Resource = "*"
      },
      {
        Sid      = "Route53DnsLookup"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:ListHostedZonesByName", "route53:GetChange"]
        Resource = "*"
      },
      {
        # 수동 생성한 도메인 존(local.route53_zone_id)의 레코드만 건드릴 수 있게 좁힘.
        # auokay.cloud -> dambda.shop 전환 중이라, state에 아직 남아있는 옛 zone(auokay.cloud)
        # 레코드를 Terraform이 destroy할 수 있도록 잠깐 두 zone 다 열어둠 - state에서 옛
        # zone 리소스가 완전히 정리되면 old_route53_zone_id는 지워도 됨
        Sid    = "Route53ZoneRecordManagement"
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/${local.route53_zone_id}",
          "arn:aws:route53:::hostedzone/${local.old_route53_zone_id}",
        ]
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
      },
      {
        # api_gateway 모듈의 WAFv2 Web ACL (REGIONAL, 로그인 rate limit + 관리형 룰셋).
        # ListAvailableManagedRuleGroups는 리소스 단위 스코프를 지원 안 해서 "*"
        Sid    = "WafManagement"
        Effect = "Allow"
        Action = [
          "wafv2:CreateWebACL",
          "wafv2:DeleteWebACL",
          "wafv2:GetWebACL",
          "wafv2:UpdateWebACL",
          "wafv2:ListWebACLs",
          "wafv2:TagResource",
          "wafv2:UntagResource",
          "wafv2:ListTagsForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "wafv2:GetWebACLForResource"
        ]
        Resource = [
          "arn:aws:wafv2:*:${local.account_id}:regional/webacl/${local.app_name_prefix}-*",
          # Web ACL이 AWS 관리형 룰그룹(Core rule set 등)을 참조할 때 CreateWebACL/
          # UpdateWebACL이 webacl 리소스 권한과는 별개로 이 managedruleset 패턴에 대한
          # 권한도 따로 요구함(실제 룰그룹은 AWS 소유인데도 계정 ID 기준으로 체크됨) -
          # 안 넣으면 "not authorized ... on resource ... regional/managedruleset/*/*"
          "arn:aws:wafv2:*:${local.account_id}:regional/managedruleset/*/*",
          "arn:aws:apigateway:*::/apis/*"
        ]
      },
      {
        Sid      = "WafManagedRuleGroupLookup"
        Effect   = "Allow"
        Action   = ["wafv2:ListAvailableManagedRuleGroups"]
        Resource = "*"
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
          "ecs:ListTaskDefinitions",
          # default_tags 때문에 task definition도 태그 대상이 됨 - 위 EcsClusterAndService
          # statement의 Resource 패턴(cluster/service)엔 task-definition ARN이 안 걸려서
          # 여기 별도로 추가함
          "ecs:TagResource",
          "ecs:ListTagsForResource"
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
          # push 시 자동 취약점 스캔(scan_on_push) 설정용
          "ecr:PutImageScanningConfiguration",
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
        # modules/eks가 Tavily SecureString을 data source(with_decryption=true)로 직접 읽어서
        # k8s Secret으로 옮겨 심음 - 예전엔 ECS 실행 롤이 이 복호화를 대신해줬지만, 이제 CI
        # 자신의 롤이 plan/apply 시점에 직접 복호화해야 함
        Sid      = "KmsDecryptForSsm"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = "arn:aws:kms:*:${local.account_id}:alias/aws/ssm"
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
          "cognito-idp:TagResource",
          # 소셜 로그인(Hosted UI 도메인 + Google IdP) 추가로 필요해진 액션
          "cognito-idp:CreateUserPoolDomain", "cognito-idp:DeleteUserPoolDomain",
          "cognito-idp:CreateIdentityProvider", "cognito-idp:DeleteIdentityProvider", "cognito-idp:UpdateIdentityProvider"
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

# ===================== 3-5. eks: EKS(Fargate) 클러스터 =====================
# ECS와 병행 구성하는 modules/eks 전용 - compute 정책이 이미 17개 statement로 제일 커서
# (6144자 제한에 가까움) 여기 얹지 않고 별도 정책으로 분리
resource "aws_iam_policy" "eks" {
  name        = "github-actions-policy-eks"
  description = "EKS(Fargate) cluster management for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EksClusterManagement"
        Effect = "Allow"
        Action = [
          "eks:CreateCluster", "eks:DescribeCluster", "eks:DeleteCluster", "eks:UpdateClusterConfig",
          "eks:TagResource", "eks:UntagResource", "eks:ListTagsForResource",
          "eks:CreateFargateProfile", "eks:DescribeFargateProfile", "eks:DeleteFargateProfile",
          "eks:CreateAddon", "eks:DescribeAddon", "eks:DeleteAddon", "eks:UpdateAddon",
          "eks:ListAddons", "eks:DescribeAddonVersions",
          "eks:CreateAccessEntry", "eks:DeleteAccessEntry", "eks:DescribeAccessEntry", "eks:ListAccessEntries", "eks:UpdateAccessEntry",
          "eks:AssociateAccessPolicy", "eks:DisassociateAccessPolicy", "eks:ListAssociatedAccessPolicies",
          # Fargate+EC2 하이브리드 노드그룹(관리용 파드를 Fargate 최소과금에서 EC2로 이전)용 -
          # 지금까지 Fargate/Addon만 있고 NodeGroup 액션이 아예 없었음
          "eks:CreateNodegroup", "eks:DescribeNodegroup", "eks:DeleteNodegroup",
          "eks:UpdateNodegroupConfig", "eks:UpdateNodegroupVersion", "eks:ListNodegroups"
        ]
        Resource = [
          "arn:aws:eks:*:${local.account_id}:cluster/${local.app_name_prefix}-*",
          "arn:aws:eks:*:${local.account_id}:fargateprofile/${local.app_name_prefix}-*/*",
          "arn:aws:eks:*:${local.account_id}:addon/${local.app_name_prefix}-*/*/*",
          "arn:aws:eks:*:${local.account_id}:access-entry/${local.app_name_prefix}-*/*/*/*",
          "arn:aws:eks:*:${local.account_id}:nodegroup/${local.app_name_prefix}-*/*/*"
        ]
      },
      {
        # kubernetes provider가 클러스터 상태를 조회할 때/plan 단계에서 씀. 목록/설명
        # 조회 액션이라 AWS가 리소스 단위 스코프를 지원 안 함(다른 Describe*류와 동일한 이유)
        Sid      = "EksClusterAuthLookup"
        Effect   = "Allow"
        Action   = ["eks:ListClusters", "eks:AccessKubernetesApi"]
        Resource = "*"
      },
      {
        # IRSA용 OIDC Provider 등록/조회 - core 정책의 IamRoleManagement(role/*)엔
        # oidc-provider 리소스 타입이 안 걸려서 별도 statement 필요
        Sid    = "EksOidcProvider"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:ListOpenIDConnectProviderTags"
        ]
        Resource = ["arn:aws:iam::${local.account_id}:oidc-provider/oidc.eks.*.amazonaws.com/id/*"]
      },
      {
        # EKS Secrets 봉투암호화용 CMK(modules/eks의 aws_kms_key.eks_secrets/aws_kms_alias.eks_secrets).
        # CreateKey 시점엔 키 ARN이 아직 없어서(랜덤 생성) 리소스 스코프 자체가 불가능함 -
        # CognitoUserPool statement와 동일한 이유로 "*" 사용
        Sid    = "EksSecretsKms"
        Effect = "Allow"
        Action = [
          "kms:CreateKey", "kms:DescribeKey", "kms:TagResource", "kms:UntagResource",
          "kms:ListResourceTags", "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion",
          "kms:EnableKeyRotation", "kms:DisableKeyRotation", "kms:GetKeyRotationStatus",
          "kms:CreateAlias", "kms:DeleteAlias", "kms:UpdateAlias", "kms:ListAliases",
          # aws_kms_key 리소스는 생성 직후 정책을 읽어서 state에 저장함(drift 확인용) -
          # GetKeyPolicy가 없으면 CreateKey 자체는 성공해도 그 다음 read 단계에서 막힘
          "kms:GetKeyPolicy",
          # aws_eks_cluster가 encryption_config로 이 키를 쓰려면, EKS 서비스가 클러스터를
          # 대신해서 이 키를 쓸 수 있도록 CreateCluster 호출자(이 롤)가 grant를 내줘야 함 -
          # 없으면 "User not authorized to perform kms:CreateGrant"로 클러스터 생성 자체가 막힘
          "kms:CreateGrant", "kms:RevokeGrant", "kms:ListGrants"
        ]
        Resource = "*"
      },
      {
        # EKS 컨트롤플레인 감사 로그(api/audit/authenticator) 대상 로그 그룹
        # (modules/eks의 aws_cloudwatch_log_group.eks_cluster) - data 정책의 CloudWatchLogs
        # statement(/eks/* 패턴, backend_foundation 앱 로그용)와는 경로 자체가 달라서
        # (/aws/eks/... vs /eks/...) 별도 statement 필요
        Sid    = "EksClusterLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
          "logs:ListTagsForResource"
        ]
        # CloudWatch Logs의 태그 관련 액션(CreateLogGroup에 태그를 같이 넘기는 경우 포함,
        # default_tags로 project=dambda가 자동으로 붙어서 여기 해당됨)은 로그그룹 ARN 끝에
        # ":*"가 붙어야 매칭되는 AWS의 잘 알려진 특이사항 - 접미사 없는 형태만으론
        # "logs:TagResource ... additional permission required"로 막힘. 두 형태 다 넣어둠
        Resource = [
          "arn:aws:logs:*:${local.account_id}:log-group:/aws/eks/${local.app_name_prefix}-*/cluster",
          "arn:aws:logs:*:${local.account_id}:log-group:/aws/eks/${local.app_name_prefix}-*/cluster:*"
        ]
      }
    ]
  })
}

# ===================== 3-6. observability: GuardDuty/Cost Anomaly/Alarm/Chatbot =====================
# compute 정책이 이미 17개 statement로 6144자 제한에 가장 근접해서(eks를 별도로 뺐던 것과
# 같은 이유) 이번에 추가하는 보안/알림 관련 권한도 여기 안 얹고 새 정책으로 분리함
resource "aws_iam_policy" "observability" {
  name        = "github-actions-policy-observability"
  description = "GuardDuty, Cost Anomaly Detection, CloudWatch Alarms, EventBridge, Chatbot for dambda CI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # 디텍터 ID가 생성 전엔 알 수 없어 리소스 단위 스코프 불가
        Sid    = "GuardDutyManagement"
        Effect = "Allow"
        Action = [
          "guardduty:CreateDetector",
          "guardduty:DeleteDetector",
          "guardduty:GetDetector",
          "guardduty:UpdateDetector",
          "guardduty:TagResource",
          "guardduty:ListDetectors",
          # default_tags로 디텍터도 태그 대상이 되면서 apply 후 태그 조회가 붙음
          "guardduty:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        # Cost Explorer 계열 액션은 리소스 단위 스코프를 지원 안 함
        Sid    = "CostAnomalyDetection"
        Effect = "Allow"
        Action = [
          "ce:CreateAnomalyMonitor",
          "ce:DeleteAnomalyMonitor",
          "ce:GetAnomalyMonitors",
          "ce:CreateAnomalySubscription",
          "ce:DeleteAnomalySubscription",
          "ce:GetAnomalySubscriptions",
          "ce:TagResource",
          # default_tags로 모니터도 태그 대상이 되면서 apply 후 태그 조회가 붙음
          "ce:ListTagsForResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchAlarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:DescribeAlarms",
          # default_tags로 알람도 태그 대상이 되면서 apply 후 태그 조회(ListTagsForResource)가 붙음
          "cloudwatch:ListTagsForResource"
        ]
        Resource = "arn:aws:cloudwatch:*:${local.account_id}:alarm:${local.app_name_prefix}-*"
      },
      {
        # GuardDuty Finding -> ops_alerts SNS 전달용 EventBridge 규칙
        Sid    = "EventBridgeRuleForGuardDuty"
        Effect = "Allow"
        Action = [
          "events:PutRule",
          "events:DeleteRule",
          "events:PutTargets",
          "events:RemoveTargets",
          "events:DescribeRule",
          # default_tags로 규칙도 태그 대상이 되면서 apply 후 태그 조회가 붙음
          "events:ListTagsForResource",
          # aws_cloudwatch_event_target이 apply 후 상태를 읽어올 때 씀(규칙 자체가 아니라
          # 그 규칙에 달린 target 목록 조회라 DescribeRule과 별개 액션)
          "events:ListTargetsByRule"
        ]
        Resource = "arn:aws:events:*:${local.account_id}:rule/${local.app_name_prefix}-*"
      },
      {
        # Slack 채널 설정 리소스는 계정 전체에 걸친 개념이라 리소스 단위 스코프 미지원
        Sid    = "ChatbotManagement"
        Effect = "Allow"
        Action = [
          "chatbot:CreateSlackChannelConfiguration",
          "chatbot:DeleteSlackChannelConfiguration",
          "chatbot:DescribeSlackChannelConfigurations",
          "chatbot:UpdateSlackChannelConfiguration",
          "chatbot:TagResource",
          # default_tags로 이 리소스도 태그 대상이 되면서 apply 후 태그 조회가 붙음
          "chatbot:ListTagsForResource"
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

resource "aws_iam_role_policy_attachment" "eks" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.eks.arn
}

resource "aws_iam_role_policy_attachment" "observability" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.observability.arn
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