# DAMBDA (담다)

한국을 방문하는 관광객에게 과자·기념품 아이템을 추천해주는 앱의 Flutter 데모입니다.
제공된 목업 디자인(홈 피드 / 상품 상세 / 좋아요 그리드)을 기반으로 실제 동작하는 화면을 구현했습니다.

백엔드 없이 로컬 샘플 데이터로만 동작하는 프론트엔드 데모입니다.

## 화면 구성

하단 탭 4개로 구성됩니다.

- **홈** — 상품 피드. 관광객 추천 배너와 "여행자 픽" 뱃지 표시
- **카테고리** — 스낵/캔디/과자/라면 등 카테고리 필터 칩으로 상품 목록 필터링
- **좋아요** — 찜한 상품을 3열 그리드로 표시
- **마이** — 프로필, 좋아요/둘러본 아이템 통계

상품을 탭하면 상세 화면(큰 이미지, 가격, 좋아요, 댓글 목록·입력)으로 이동합니다.

## 프로젝트 구조

```
lib/
  main.dart                    앱 진입점
  theme/app_theme.dart         색상·테마
  models/product.dart          Product, Comment 모델
  data/sample_products.dart    샘플 상품 데이터
  state/app_state.dart         좋아요/댓글 상태 (ChangeNotifier 싱글턴)
  screens/                     홈/카테고리/좋아요/마이/상세/하단 탭 셸
  widgets/                     앱바, 상품 리스트/그리드 타일 등 공용 위젯
```

## 로컬에서 실행하기

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=https://<배포된-API-Gateway-주소>
flutter run -d windows --dart-define=API_BASE_URL=https://<배포된-API-Gateway-주소>
```

`--dart-define=API_BASE_URL=...`을 빼면 앱이 존재하지 않는 `http://localhost:8080`으로 로그인 요청을 보내다가 **로그인/회원가입 버튼이 무한 로딩처럼 멈춰요.** 실제 주소는 terraform 폴더에서 아래로 확인:

```bash
cd ../terraform
terraform output api_gateway_endpoint
```

## 테스트 / 정적 분석

```bash
flutter analyze
flutter test
```

## 모바일(APK)로 테스트하기

```bash
# 실기기 사이드로딩용 릴리스 APK (아키텍처별로 분리, 용량 작음)
flutter build apk --release --split-per-abi
```

빌드 결과는 `build/app/outputs/flutter-apk/`에 생성됩니다. 최신 안드로이드 폰 대부분은
`app-arm64-v8a-release.apk`를 사용하면 됩니다. `adb install <파일>`로 설치하거나,
APK 파일을 폰으로 전송해 직접 열어 설치할 수 있습니다(출처를 알 수 없는 앱 설치 허용 필요).

이 APK는 기본 디버그 키로 서명되어 있어 사이드로딩 테스트용으로는 문제없지만,
플레이스토어에 배포하려면 별도 키스토어로 다시 서명해야 합니다.

## 웹 버전 AWS 배포

`../terraform` 에 정의된 인프라 중 `module.storage`(S3 정적 웹 호스팅, 서울 리전)를
사용해 프론트엔드만 배포합니다. 지금 앱은 백엔드가 없는 데모라 `network`/`alb`/
`api_gateway`/`compute` 모듈은 배포하지 않았습니다.

```bash
# 1. 웹 빌드
flutter build web --release

# 2. S3에 업로드 (build/web 폴더 전체가 그대로 웹사이트가 됩니다)
aws s3 sync build/web s3://my-app-dev-static-site-793001767302 --delete --region ap-northeast-2
```

**테스트 URL:** http://my-app-dev-static-site-793001767302.s3-website.ap-northeast-2.amazonaws.com

- S3 웹사이트 호스팅 자체 한계로 HTTP만 지원합니다(HTTPS 아님). HTTPS가 필요해지면
  `terraform/modules/storage` 앞단에 CloudFront(+OAC)를 추가하면 됩니다.
- 버킷은 테스트 목적상 퍼블릭으로 열려 있어 URL을 아는 누구나 접속할 수 있습니다.
- 리소스를 정리하려면: `terraform destroy -target=module.storage` (terraform 폴더에서 실행)
