# DAMBDA (담다)

한국을 방문하는 관광객에게 과자·화장품·생활용품을 추천해주는 앱입니다. 처음엔 로컬 샘플 데이터만
쓰는 Flutter 프론트엔드 데모로 시작했지만, 지금은 **로그인/회원가입, 실제 DB 기반 상품 카탈로그,
좋아요, 사진 첨부 리뷰(AI 검열 포함), 4개 언어(한국어/영어/일본어/중국어) 번역**까지 갖춘
Flutter + Node.js/Express + AWS 풀스택 서비스입니다.

## 기능

- **로그인/회원가입** — Cognito 기반 인증. Flutter는 Cognito를 직접 호출하지 않고 자체
  백엔드(`POST /auth/signup`, `/login`, `GET /auth/me`)를 거칩니다.
- **상품 카탈로그** — DynamoDB에 저장된 65개 실상품(스낵/화장품/생활용품). 상품명·추천이유·
  할인정보는 영어/일본어/중국어로 미리 번역되어 있어 언어 전환 시 즉시 반영됩니다.
- **좋아요** — 로그인한 유저별로 DynamoDB에 저장, 로그아웃/재로그인해도 유지됩니다.
- **리뷰** — 별점 + 텍스트 + 선택적 사진. 등록/수정 시 Lambda(Rekognition + Comprehend)로
  텍스트·이미지 검열을 거쳐 부적절한 내용은 자동 거부됩니다. 본인 리뷰만 수정/삭제 가능.
  다른 언어로 조회하면 처음 조회되는 시점에 AWS Translate로 번역 후 캐싱됩니다.
- **다국어 지원** — 앱 UI 자체(버튼/메뉴/에러 메시지)는 정적으로 4개 언어 번역이 내장되어
  있고, 마이 화면에서 언어를 바꿀 수 있습니다. 상품 데이터·리뷰 같은 콘텐츠는 AWS Translate로
  번역됩니다.
- **URL 기반 라우팅** — 하단 탭(홈/카테고리/좋아요/마이) 이동은 브라우저 URL과 연동되어 있어
  새로고침해도 있던 화면 그대로 유지됩니다. (예외: 상품 상세 화면은 뒤로가기는 정상이지만
  새로고침 시 이전 탭으로 돌아갑니다 — go_router 라이브러리의 알려진 한계)

## 화면 구성

하단 탭 4개로 구성됩니다.

- **홈** — 상품 피드, 관광객 추천 배너
- **카테고리** — 스낵/화장품/생활용품 카테고리 필터 칩으로 상품 목록 필터링
- **좋아요** — 찜한 상품을 3열 그리드로 표시
- **마이** — 프로필, 좋아요/둘러본 아이템 통계, **언어 설정**, 로그아웃

상품을 탭하면 상세 화면(큰 이미지, 가격, 추천이유, 할인정보, 좋아요, 리뷰 목록·작성/수정/삭제)
으로 이동합니다. 비로그인 상태로는 로그인 화면만 보이고, 로그인해야 나머지 화면에 접근할 수
있습니다.

## 저장소 구조

```
dambda/          Flutter 앱 (이 폴더)
backend/         로그인/상품/리뷰 API (Node.js/Express, ECS Fargate에서 실행)
terraform/       AWS 인프라 (VPC/ALB/API Gateway/ECS/Cognito/DynamoDB/S3/Lambda)
lambda/          리뷰 검열 Lambda 소스 (Rekognition + Comprehend)
json/            상품 원본 데이터 (seed 스크립트가 이걸 읽어 DynamoDB에 번역까지 채워 넣음)
```

### `dambda/lib/` 구조

```
lib/
  main.dart                    앱 진입점, 로케일/라우터 초기화
  router.dart                  go_router 기반 URL 라우팅 + 로그인 게이팅
  theme/app_theme.dart         색상·테마
  models/                      Product, Review 모델 (다국어 번역 필드 포함)
  l10n/                        앱 UI 문자열 번역 (app_ko/en/ja/zh.arb)
  services/                    백엔드 API 클라이언트 (auth/product/review)
  state/                       ChangeNotifier 싱글턴 상태 (app/auth/locale)
  screens/                     로그인/회원가입/홈/카테고리/좋아요/마이/상품상세
  widgets/                     앱바, 상품 리스트/그리드 타일 등 공용 위젯
```

## 로컬에서 Flutter 앱 실행하기

백엔드가 AWS에 배포되어 있어야 로그인 등 실제 기능이 동작합니다. 배포된 API Gateway 주소를
`--dart-define`으로 넘겨서 실행합니다.

```bash
cd dambda
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://<배포된-API-Gateway-주소>
flutter run -d windows --dart-define=API_BASE_URL=https://<배포된-API-Gateway-주소>
```

`--dart-define=API_BASE_URL=...`을 빼면 앱이 존재하지 않는 `http://localhost:8080`으로 요청을
보내다가 **로그인/회원가입 버튼이 무한 로딩처럼 멈춰요.** 실제 주소는 terraform 폴더에서 확인:

```bash
cd ../terraform
terraform output api_gateway_endpoint
```

### 테스트 / 정적 분석

```bash
flutter analyze
flutter test
```

### 모바일(APK)로 테스트하기

```bash
flutter build apk --release --split-per-abi
```

빌드 결과는 `build/app/outputs/flutter-apk/`에 생성됩니다. 최신 안드로이드 폰 대부분은
`app-arm64-v8a-release.apk`를 사용하면 됩니다. `adb install <파일>`로 설치하거나, APK 파일을
폰으로 전송해 직접 열어 설치할 수 있습니다(출처를 알 수 없는 앱 설치 허용 필요). 기본 디버그
키로 서명되어 있어 사이드로딩 테스트용으로만 쓰고, 플레이스토어 배포 시엔 별도 키스토어로
다시 서명해야 합니다.

## AWS에 처음부터 배포하기

전부 수동 배포입니다(CI/CD 없음). 순서대로:

**1. 인프라 생성**
```bash
cd terraform
terraform apply
```
네트워크(VPC/NAT), ALB, API Gateway, ECS Fargate 클러스터, Cognito, DynamoDB(4개 테이블),
S3(정적 사이트 + 리뷰 사진), 검열 Lambda가 한 번에 올라갑니다. **NAT Gateway/ALB/Fargate가
포함돼 있어 켜져 있는 동안 시간당 비용이 발생합니다.**

**2. 백엔드 이미지 빌드 & 배포**
```bash
cd backend
aws ecr get-login-password --region ap-northeast-2 | docker login --username AWS --password-stdin <계정ID>.dkr.ecr.ap-northeast-2.amazonaws.com
docker build --platform linux/amd64 -t <계정ID>.dkr.ecr.ap-northeast-2.amazonaws.com/my-app-dev-backend:latest .
docker push <계정ID>.dkr.ecr.ap-northeast-2.amazonaws.com/my-app-dev-backend:latest
aws ecs update-service --cluster my-app-dev-cluster --service my-app-dev-service --force-new-deployment --region ap-northeast-2
```
`terraform apply`로 ECR 리포지토리가 새로 만들어지면 처음엔 비어있어서, 이 단계 전에는 ECS가
`CannotPullContainerError`로 계속 실패합니다 — 인프라만 올리고 이 단계를 건너뛰지 마세요.

**3. 상품 카탈로그 시딩**
```bash
AWS_REGION=ap-northeast-2 PRODUCT_CATALOG_TABLE_NAME=my-app-dev-product-catalog \
  node backend/scripts/seed-products.js
```
`json/items.json`을 읽어 65개 상품을 DynamoDB에 저장하면서, AWS Translate로 영어/일본어/중국어
번역까지 같이 채워 넣습니다(몇 분 정도 걸립니다).

**4. Flutter 웹 빌드 & S3 배포**
```bash
cd terraform && terraform output api_gateway_endpoint   # 주소 확인
cd ../dambda
flutter build web --release --dart-define=API_BASE_URL=<위에서 확인한 주소>
aws s3 sync build/web s3://my-app-dev-static-site-793001767302 --delete --region ap-northeast-2
```

**배포된 사이트 주소**는 `terraform output static_site_url`로 확인합니다(S3 웹사이트 호스팅
한계로 HTTPS는 지원하지 않습니다. 필요하면 CloudFront를 앞단에 추가해야 합니다). 버킷은 테스트
목적상 퍼블릭으로 열려 있습니다.

Flutter 코드만 바꾼 경우엔 4번만, 백엔드 코드만 바꾼 경우엔 2번만 다시 하면 됩니다. **웹 코드를
바꾸고 `flutter build web`만 실행하면 로컬에만 반영되고 실제 배포 사이트는 안 바뀝니다** —
`aws s3 sync`까지 해야 반영됩니다.

## 리소스 정리하기

```bash
cd terraform
terraform destroy
```
NAT Gateway/ALB/Fargate가 시간당 과금되는 리소스라, 테스트가 끝나면 정리하는 걸 권장합니다.
S3 버킷(리뷰 사진)에 파일이 남아있으면 `BucketNotEmpty` 에러로 삭제가 막힐 수 있는데, 이때는
`aws s3 rm s3://<버킷명> --recursive`로 먼저 비운 뒤 `terraform destroy`를 다시 실행하면 됩니다.
