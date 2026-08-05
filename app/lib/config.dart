// 백엔드가 배포될 때마다(terraform apply 결과 API Gateway 엔드포인트가 바뀔 때마다)
// --dart-define=API_BASE_URL=... 로 갱신해서 빌드/실행해야 함 (자동화된 CI/CD가 아직 없음)
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8080',
);
