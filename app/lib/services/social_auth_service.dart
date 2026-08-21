import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'api_exception.dart';
import 'http_timeout.dart';
import 'social_auth_platform.dart';

// 배포 시 --dart-define으로 채워야 함(예: COGNITO_DOMAIN=https://my-app-dev-<account>.auth.
// ap-northeast-2.amazoncognito.com, COGNITO_CLIENT_ID=<app client id>) - modules/cognito가
// google_oauth_client_id/secret 없이 만든 상태(Hosted UI 도메인만 존재)면 여기 도메인/클라이언트
// ID 자체는 유효해도 startGoogleLogin()이 리다이렉트하는 화면에서 "Google" IdP가 없다고 뜸
const _domain = String.fromEnvironment('COGNITO_DOMAIN');
const _clientId = String.fromEnvironment('COGNITO_CLIENT_ID');
const _redirectUri = String.fromEnvironment(
  'COGNITO_REDIRECT_URI',
  defaultValue: 'http://localhost:8080/auth/callback',
);
const _verifierKey = 'dambda_oauth_verifier';
const _stateKey = 'dambda_oauth_state';

class SocialAuthService {
  String _randomUrlSafe(int byteLength) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  void startGoogleLogin() {
    if (_domain.isEmpty || _clientId.isEmpty) {
      throw const ApiException(500, 'Google 로그인 설정이 배포되지 않았습니다.');
    }
    final verifier = _randomUrlSafe(64);
    final state = _randomUrlSafe(32);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    writeSocialSession(_verifierKey, verifier);
    writeSocialSession(_stateKey, state);

    final uri = Uri.parse('$_domain/oauth2/authorize').replace(
      queryParameters: {
        'identity_provider': 'Google',
        'response_type': 'code',
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'scope': 'openid email profile aws.cognito.signin.user.admin',
        'state': state,
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
      },
    );
    redirectToSocialLogin(uri.toString());
  }

  // Cognito Hosted UI가 PKCE 인가코드 교환까지 끝낸 뒤 토큰을 돌려줌 - accessToken은
  // AuthService.completeSocialSession()으로 넘겨 앱 전용 프로필을 만들거나 조회하고,
  // refreshToken은 auth_state.dart의 기존 자동 갱신 스케줄러에 그대로 태움(일반 로그인과 동일하게)
  Future<({String accessToken, String refreshToken})> exchangeCallback(Uri callbackUri) async {
    final error = callbackUri.queryParameters['error'];
    if (error != null) throw const ApiException(400, 'Google 로그인이 취소됐습니다.');
    final code = callbackUri.queryParameters['code'];
    final state = callbackUri.queryParameters['state'];
    final expectedState = readSocialSession(_stateKey);
    final verifier = readSocialSession(_verifierKey);
    if (code == null || state == null || state != expectedState || verifier == null) {
      throw const ApiException(400, '유효하지 않은 로그인 요청입니다. 다시 시도해주세요.');
    }

    final response = await http
        .post(
          Uri.parse('$_domain/oauth2/token'),
          headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'grant_type': 'authorization_code',
            'client_id': _clientId,
            'code': code,
            'redirect_uri': _redirectUri,
            'code_verifier': verifier,
          },
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    clearSocialSession(_stateKey);
    clearSocialSession(_verifierKey);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, 'Google 로그인 토큰을 발급하지 못했습니다.');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
    );
  }
}
