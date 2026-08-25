# dambda — AWS 기반 글로벌 여행 후기 서비스

![Terraform CI/CD](https://github.com/ahowme12/dambda/actions/workflows/terraform.yml/badge.svg)
![Deploy Backend](https://github.com/ahowme12/dambda/actions/workflows/deploy-backend.yml/badge.svg)
![Deploy Frontend](https://github.com/ahowme12/dambda/actions/workflows/deploy-frontend.yml/badge.svg)

> Translate → Comprehend → Rekognition으로 이어지는 AI 파이프라인을 자동으로 거치고,
> 최종 판단이 필요한 콘텐츠만 관리자 콘솔로 올라갑니다.

|  | 역할 |
|---|---|
| 📱 **Client** (Flutter, iOS/Android/Web) | 여행지 탐색, 리뷰 작성(텍스트+사진), 좋아요, 알림, Bedrock 기반 상품 Q&A |
| ⚙️ **Admin** (backend `/admin` API) | AI가 자동 차단/보류시킨 콘텐츠 최종 검토, 상품 카탈로그 관리 |

## AWS 구성도

<img src="./담다 구성도0824_v2.drawio.png" alt="아키텍처 다이어그램" width="800">

## 🌐 End-to-End 트래픽 처리 흐름

사용자가 리뷰(텍스트+이미지)를 업로드했을 때 실제로 인프라를 타고 흐르는 경로입니다.

### 1단계 — 라우팅 & 정적 자원 (Edge Layer)

- **Route 53**: 서울(운영)과 us-east-1(파일럿 라이트 DR)에 각각 API Gateway/ALB 스택을 구성해두고, 리전 승격 시 Route 53만 전환하면 되는 구조로 설계
- **CloudFront + OAC**: Flutter Web 정적 빌드는 CloudFront가 캐싱해서 서빙 — S3 버킷 자체는 완전히 비공개로 잠그고 Origin Access Control로만 읽게 함
- **ACM**: CloudFront(us-east-1 고정 요건)와 서비스 도메인 모두 ACM 인증서로 HTTPS 강제

### 2단계 — 웹 보안 & 인증 (Ingress Layer)

- **AWS WAF**: 내부 ALB 앞단에 관리형 규칙 그룹(Common/KnownBadInputs/IP Reputation) + 커스텀 rate-based 규칙(엔드포인트별 5분당 요청 한도)을 붙여서 애플리케이션 로직 앞에서 1차 방어
- **API Gateway (HTTP API) + Cognito JWT Authorizer**: 라우트별로 인증 요구 여부를 다르게 설정, VPC Link로 내부망 ALB와 연결 — API Gateway가 퍼블릭에 노출되는 유일한 진입점
- **Cognito**: 이메일/비밀번호 + Google 소셜 로그인, Hosted UI

### 3단계 — 애플리케이션 (Compute Layer)

- **EKS(Fargate)**: backend(Express.js) 파드가 Fargate 위에서 실행, HPA/PodDisruptionBudget으로 무중단 스케일링
- **EC2 관리형 노드그룹**: ArgoCD/ALB Controller/CoreDNS/metrics-server 같은 클러스터 운영용 파드는 실사용량 대비 Fargate 과금이 비효율적이라 작은 EC2 노드 1대로 분리(자세한 배경은 아래 Trouble & Resolution 참고)
- **ArgoCD(GitOps)**: `k8s/` 디렉터리의 매니페스트를 감시해서 자동 동기화 — CI는 이미지 태그만 커밋하고 클러스터에 직접 명령하지 않음
- **DynamoDB (Global Tables)**: 사용자/상품/리뷰/좋아요/모더레이션 이벤트 테이블을 Seoul↔us-east-1로 리전 간 복제

### 4단계 — AI 기반 미디어 업로드 & 유해 콘텐츠 검열 파이프라인

1. 리뷰 사진은 검열 전까지 `quarantine` 버킷(완전 비공개)에 원본 그대로 격리 저장
2. 업로드 이벤트가 SQS 큐에 쌓이고, Step Functions가 리뷰 검열 worker Lambda를 호출
3. **Translate**로 리뷰 텍스트를 자동 언어감지 후 영어로 변환(Comprehend가 영어만 지원하기 때문)
4. **Comprehend `DetectToxicContent`**로 텍스트 독성/스팸 여부, **Rekognition `DetectModerationLabels`**로 이미지 내 부적절한 요소를 병렬로 분석
5. 통과한 콘텐츠만 `review_photos`(공개) 버킷으로 이동해 서비스에 노출되고, 걸린 콘텐츠는 `moderation_events` 테이블에 기록되어 관리자 콘솔(`/admin/moderation-events`)에서 사람이 최종 승인/삭제
6. 리뷰 표시 시 원문은 **Bedrock**으로 번역(과거엔 AWS Translate를 썼으나 사용량 대비 비용 절감을 위해 Bedrock으로 교체), 상품 Q&A는 Bedrock 임베딩 기반 RAG로 응답

### 5단계 — 운영 & 모니터링 (Operations Layer)

- **CloudWatch**: ALB/API Gateway/DynamoDB/Lambda 지표, 로그 그룹
- **Amazon Managed Prometheus + ADOT 사이드카**: backend 파드가 노출하는 애플리케이션 지표(요청 수, p95 레이턴시)를 사이드카가 긁어 AMP로 remote-write
- **Amazon Managed Grafana**: CloudWatch + Prometheus 데이터소스를 한 대시보드에 묶어 트래픽/보안(WAF)/DB/비동기 파이프라인/애플리케이션 계층별로 시각화
- **GuardDuty + SNS/Slack**: 위협 탐지와 예산 이상탐지(Cost Anomaly Detection) 알림을 Slack으로 전달
- **IAM/IRSA**: 클러스터 노드 인증과 파드 단위 AWS 권한(IRSA)을 분리, 전 구간 최소 권한 원칙

## 🛠️ Tech Stack

| 분류 | 서비스 | 역할 |
|---|---|---|
| **Edge & CDN** | Route 53, CloudFront, ACM | 리전 라우팅, 정적 자원 캐싱, HTTPS |
| **Network** | VPC, NAT Gateway, VPC Link, ALB(internal), API Gateway(HTTP API) | Public/Private 서브넷 분리, 내부망 전용 ALB |
| **Compute** | EKS(Fargate + EC2 관리형 노드그룹), ArgoCD | 워크로드별 컴퓨트 분리, GitOps 배포 |
| **Data** | DynamoDB(Global Tables), S3(교차 리전 복제) | 정형 데이터/미디어 저장, 멀티 리전 내구성 |
| **Auth** | Cognito(이메일 + Google), IAM/IRSA | 사용자 인증, 파드별 최소 권한 AWS 접근 |
| **Security** | WAF, GuardDuty, Checkov, Trivy | 웹 공격 방어, 위협 탐지, IaC/이미지 취약점 스캔 |
| **AI** | Bedrock, Comprehend, Rekognition, Translate | 번역, 상품 Q&A(RAG), 텍스트/이미지 유해 콘텐츠 검열 |
| **Async Pipeline** | SQS, Step Functions, Lambda | 리뷰 검열 파이프라인 오케스트레이션 |
| **Observability** | CloudWatch, Amazon Managed Prometheus, ADOT, Amazon Managed Grafana | 인프라/애플리케이션 지표 수집 및 시각화 |
| **IaC & DevOps** | Terraform, GitHub Actions(OIDC), ArgoCD | 코드 기반 멀티 리전 배포, 무키(無key) CI/CD |

## 🤖 Terraform 기반 인프라 자동화 (IaC)

CloudFormation 대신 **Terraform**으로 서울(운영) + us-east-1(파일럿 라이트 DR) 두 리전을 같은
모듈 집합(`modules/network`, `modules/eks`, `modules/storage` …)으로 구성했습니다.

- **모듈 재사용**: 같은 모듈을 provider만 바꿔 두 리전에 그대로 호출 — 리전 하나를 완전한
  스택으로 복제하는 데 코드 중복이 거의 없음
- **CI/CD 3단 분리**: `terraform.yml`(인프라) → `deploy-backend.yml` / `deploy-frontend.yml`이
  `workflow_run`으로 뒤따라오는 구조 — 인프라가 먼저 존재해야 하는 애플리케이션 배포의 순서 문제를
  워크플로우 트리거로 해결
- **OIDC 연동**: GitHub Actions가 장기 액세스 키 없이 IAM Role을 임시로 assume — 자격 증명이
  저장소/시크릿에 평문으로 남지 않음
- **정적 분석**: Checkov(IaC 설정 실수)와 Trivy(컨테이너 이미지 CVE)를 CI에 상시 연결

## 🚀 Key Features

- **🌐 멀티 리전 파일럿 라이트 DR**: 서울을 운영 리전으로, us-east-1은 네트워크/ALB/API
  Gateway/S3 복제본을 상시 유지하고 컴퓨트(EKS)만 켜면 승격되는 구조로 설계
- **🤖 AI 3단 검열 파이프라인**: Translate → Comprehend(텍스트) / Rekognition(이미지) 자동
  분석 후, 애매한 콘텐츠만 관리자 콘솔로 에스컬레이션하는 휴먼-인-더-루프 설계
- **📦 S3 교차 리전 복제**: 사용자 업로드 콘텐츠(리뷰 사진/상품 이미지)는 리전 장애에도
  살아남도록 us-east-1로 자동 복제, 재생성 가능한 정적 빌드/미검증 콘텐츠는 제외해서 비용 통제
- **🔐 GitOps 기반 배포**: ArgoCD가 `k8s/` 매니페스트를 감시 — CI는 이미지 태그를 git에
  커밋할 뿐, 클러스터에 직접 `kubectl apply`하지 않음
- **📊 관측 가능성**: CloudWatch(인프라) + Amazon Managed Prometheus/ADOT(애플리케이션)를
  하나의 Grafana 대시보드로 통합
- **💰 비용 인지 설계**: 워크로드 특성에 따라 컴퓨트를 분리(운영 트래픽=Fargate, 상시 상주
  시스템 파드=EC2), 번역 API를 사용량 기반으로 재검토하는 등 전 구간에서 실사용량 대비
  과금 구조를 계속 점검

## Trouble & Resolution

### 🛠️ Terraform 빈 Resource 배열로 인한 IAM 권한 정책 생성 실패

**문제 상황**
어느 시점부터 회원가입/상품 조회 등 backend가 AWS 서비스를 호출하는 모든 기능이 한꺼번에
실패하기 시작함. 에러 로그만 봐서는 어떤 서비스 하나가 문제인지 특정이 안 됨 — DynamoDB도,
S3도, Bedrock도 전부 권한 오류를 냄.

**원인 분석**
`terraform apply -target=module.backend_foundation.aws_iam_policy.backend_task_policy`로
문제를 좁혀서 직접 재현하니 `MalformedPolicyDocument: Policy statement must contain
resources`가 그대로 드러남. 이미 안 쓰는 Lambda invoke 권한 블록이 `Resource =
var.lambda_invoke_arns`를 참조하고 있었는데, 이 변수가 빈 배열(`[]`)로 넘어오면서 IAM
정책 문서 자체가 통째로 유효하지 않게 되어 있었음 — 정책 리소스 **생성 자체가 실패**해서
backend의 IRSA 롤에 커스텀 권한이 하나도 안 붙은 상태였던 것.

**해결 방안**
이미 죽은 코드였던 Lambda invoke 권한 블록과 관련 변수를 완전히 삭제. 재적용 후
`aws iam list-attached-role-policies`로 정책이 실제로 붙었는지 직접 확인하고 나서야
전체 기능이 정상화됨. 이 사건 이후로 "변수 기본값(빈 문자열/빈 배열)일 때 `validate`가
조건문을 상수로 접어버려서 실제 값이 들어가는 순간에만 터지는" 케이스를 항상 의심하는
습관이 붙음.

### 🛠️ Terraform 설정과 GitOps Manifest 불일치로 발생한 메트릭 수집 장애

**문제 상황**
Terraform의 `enable_prometheus` 변수를 켰는데도 Grafana 대시보드의 애플리케이션 지표
패널(요청 수, p95 레이턴시)이 계속 "No data"로 남아있었음.

**원인 분석**
두 가지 원인이 겹쳐 있었음.
1. backend Deployment를 ECS에서 EKS로, 다시 kubectl 직접 관리에서 ArgoCD(GitOps) 관리로
   이관하는 과정에서, "Prometheus 사이드카를 붙인다"는 원래 설계 의도가 실제 파드 스펙에는
   한 번도 반영되지 않은 채 방치되어 있었음 — Terraform 변수는 켜져 있었지만 그 변수를
   실제로 소비하는 컨테이너 자체가 없었던 것.
2. 사이드카를 붙이고 나서도 데이터가 안 뜨길래 Grafana의 Prometheus 데이터소스 설정을
   열어보니 SigV4 인증 토글이 꺼져 있었음. Terraform 코드에 `sigv4Auth`(소문자 v)로 필드명을
   잘못 써서 Grafana가 알 수 없는 키로 무시하고 있었던 것 — 같은 대시보드의 CloudWatch
   패널은 별도의 자체 인증 방식을 쓰는 플러그인이라 이 오타와 무관하게 정상 동작했던 게
   원인 특정을 더 늦춘 요인이었음.

**해결 방안**
ADOT 컬렉터를 GitOps 매니페스트에 사이드카로 직접 추가해서 backend가 노출하는
`/metrics`를 긁어 AMP로 remote-write하도록 배선하고, `sigV4Auth`로 필드명을 바로잡음.
고친 뒤 AMP에 직접 PromQL을 질의해서 실제로 데이터가 들어오는지부터 확인하고, Grafana
쪽 캐시/시간범위 문제와 진짜 파이프라인 장애를 구분해서 접근하는 방식으로 디버깅함.

### 🛠️ GitHub 저장소 이름 변경 후 CI/CD 인증이 전부 막혔던 문제

**문제 상황**
저장소 이름을 `github-actions-test`에서 `dambda`로 바꾼 뒤, CI가 AWS 자격 증명을 받아오는
단계(`sts:AssumeRoleWithWebIdentity`)에서 실패할 위험이 있었음.

**원인 분석**
GitHub Actions OIDC 연동은 장기 액세스 키 대신 매 실행마다 발급되는 JWT의 `sub` 클레임을
AWS IAM 신뢰 정책과 대조해서 인증함. 이 프로젝트의 신뢰 정책은 `repo:{owner}@{ownerId}/
{repoName}@{repoId}:...` 형태의 문자열을 그대로 `StringLike` 조건으로 갖고 있었는데,
`@숫자ID` 부분은 저장소를 다시 만들거나 다른 계정이 같은 이름을 가져가는 것(name-squatting)을
막기 위한 불변값이지만, **저장소 이름 부분(`repoName`)은 매번 토큰 발급 시점의 "현재 이름"이
그대로 들어감** — 즉 이름을 바꾸면 ID는 그대로여도 문자열 전체가 더 이상 일치하지 않아서
인증이 막힘. 코드 전체에서 저장소 이름이 하드코딩된 곳이 OIDC 신뢰 정책과 ArgoCD
`Application`의 `repoURL` 두 곳이라는 것도 이번에 다시 확인함.

**해결 방안**
두 곳 모두 새 저장소 이름으로 갱신. OIDC 신뢰 정책은 AWS 쪽 리소스라 CI를 기다릴 필요 없이
바로 `terraform apply`로 반영해서 이후 워크플로우 실행부터 곧바로 정상화함. ArgoCD의
`repoURL`은 GitHub가 예전 이름으로의 clone 요청을 당분간 새 이름으로 리다이렉트해주긴
하지만, 리다이렉트에 기대지 않고 실제 값으로 맞춰서 잠재적 실패 지점을 없앰.

### 🛠️ Fargate 관리용 파드의 실사용량 대비 과금 비효율 개선

**문제 상황**
비용을 점검하다 ArgoCD/ALB Controller/CoreDNS/metrics-server 등 클러스터 운영용 파드
9개가 Fargate의 "파드 1개 = 독립 과금 단위" 구조 때문에 상당한 비중을 차지하고 있는 걸
발견함. `kubectl top`으로 실사용량을 재보니 9개를 다 합쳐도 CPU/메모리가 작은 인스턴스
하나로 충분히 커버되는 수준이었음.

**해결 방안**
운영 트래픽을 직접 받는 backend는 그대로 Fargate에 남기고, 상시 상주하는 시스템 파드만
작은 EC2 관리형 노드그룹으로 옮기는 하이브리드 구조로 전환. Backend는 Fargate에 유지하고, HPA·PDB·복수 Replica를 적용한 상태에서 시스템 워크로드를 EC2 Managed Node Group으로 단계적으로 재배치하여 전환 중 가용성을 확보했다.
