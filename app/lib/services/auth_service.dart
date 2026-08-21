import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

export 'api_exception.dart';

class AuthTokens {
  final String accessToken;
  final String idToken;
  final String refreshToken;

  const AuthTokens({
    required this.accessToken,
    required this.idToken,
    required this.refreshToken,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      idToken: json['idToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}

class AuthService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<void> signup({
    required String email,
    required String password,
    required String nickname,
    required String country,
  }) async {
    final response = await http
        .post(
          _uri('/auth/signup'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
            'nickname': nickname,
            'country': country,
          }),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
  }

  Future<AuthTokens> login({required String email, required String password}) async {
    final response = await http
        .post(
          _uri('/auth/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return AuthTokens.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // 리프레시 토큰 자체는 이 플로우에서 로테이션 안 되므로 응답엔 accessToken/idToken만 옴 -
  // 호출한 쪽이 기존 refreshToken을 그대로 들고 있어야 함
  Future<AuthTokens> refresh(String refreshToken) async {
    final response = await http
        .post(
          _uri('/auth/refresh'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refreshToken}),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthTokens(
      accessToken: json['accessToken'] as String,
      idToken: json['idToken'] as String,
      refreshToken: refreshToken,
    );
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await http
        .post(
          _uri('/auth/password/forgot'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await http
        .post(
          _uri('/auth/password/confirm'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'code': code, 'newPassword': newPassword}),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
  }

  // Cognito Hosted UI OAuth 토큰 교환(social_auth_service.dart)까지 끝난 뒤, 그 accessToken으로
  // 이 앱 전용 프로필을 처음이면 만들고 돌려받음 (routes/auth.js social/session)
  Future<Map<String, dynamic>> completeSocialSession(String accessToken) async {
    final response = await http
        .post(_uri('/auth/social/session'), headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me(String accessToken) async {
    final response = await http
        .get(
          _uri('/auth/me'),
          headers: {'Authorization': 'Bearer $accessToken'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // GET /admin/me는 authenticate+admin 미들웨어를 통과해야만 200이 나옴(admin.js) -
  // 즉 이 응답 코드 자체가 "관리자 그룹 소속 여부"를 그대로 알려줌
  Future<bool> isAdmin(String accessToken) async {
    final response = await http
        .get(_uri('/admin/me'), headers: {'Authorization': 'Bearer $accessToken'})
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode == 200) return true;
    if (response.statusCode == 401 || response.statusCode == 403) return false;
    throw ApiException(response.statusCode, _errorMessage(response));
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? '요청에 실패했어요.';
    } catch (_) {
      return '요청에 실패했어요.';
    }
  }
}
