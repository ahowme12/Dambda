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
