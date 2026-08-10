// --dart-define=API_BASE_URL=...을 안 넘기면 이 기본값으로 감. 예전엔 존재하지 않는
// localhost:8080이라 --dart-define 없이 실행하면 모든 요청이 조용히 실패했음 - 지금은
// 현재 배포된 API Gateway 주소를 기본값으로 둬서 아무것도 안 넘겨도 동작하게 함.
// "/prod"는 WAFv2 연결 때문에 스테이지를 "$default"에서 명명 스테이지로 바꾸면서 붙은
// 경로(modules/api_gateway/main.tf 참고). terraform apply로 API Gateway를 재생성해서
// 주소가 바뀌면(리소스 삭제 후 재생성 등, 보통의 업데이트로는 안 바뀜) 이 값도 갱신해야 함
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://64cxs4uadh.execute-api.ap-northeast-2.amazonaws.com/prod',
);
