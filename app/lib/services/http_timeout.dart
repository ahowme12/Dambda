import 'api_exception.dart';

// 백엔드에 도달할 수 없을 때(잘못된 API_BASE_URL, 서버 다운 등) 요청이 무기한 멈춰서
// 로딩 스피너가 영원히 도는 것처럼 보이는 걸 막기 위한 공통 타임아웃. 모든 서비스 파일에서 재사용
const requestTimeout = Duration(seconds: 15);

Never timeoutError() {
  throw const ApiException(0, '서버에 연결할 수 없어요. 네트워크 상태나 서버 주소를 확인해주세요.');
}
