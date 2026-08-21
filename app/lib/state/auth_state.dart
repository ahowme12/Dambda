import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'app_state.dart';

const _accessTokenKey = 'dambda_access_token';
const _refreshTokenKey = 'dambda_refresh_token';

// JWT의 payload(가운데 세그먼트)를 디코딩해서 exp(만료 unix seconds)만 뽑아냄. 형식이
// 이상하면(옛날에 저장된 손상된 값 등) null을 돌려주고 호출부가 알아서 재로그인 처리하게 함
int? _jwtExpiry(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final normalized = base64Url.normalize(parts[1]);
    final payload = jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map<String, dynamic>;
    return payload['exp'] as int?;
  } catch (_) {
    return null;
  }
}

class AuthState extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  Timer? _refreshTimer;
  UserProfile? profile;
  bool isAdmin = false;
  bool isLoading = false;
  String? lastError;

  bool get isLoggedIn => _accessToken != null && profile != null;
  String? get accessToken => _accessToken;

  // flutter_secure_storage(웹)는 브라우저 Web Crypto API를 쓰는데 이게 HTTPS/localhost
  // 같은 "secure context"에서만 동작함. 지금 S3 정적 호스팅은 HTTP라 여기서 예외가 남 -
  // 로그인 자체(백엔드 호출)는 성공해도 토큰 저장이 실패하면서 화면이 조용히 멈추는 걸 방지하려고
  // 저장 실패를 로그인 성공/실패와 분리함 (HTTPS로 옮기면 자동으로 새로고침 후에도 로그인 유지됨)
  Future<String?> _readStorage(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('secure storage read failed (non-fatal): $e');
      return null;
    }
  }

  Future<void> _writeStorage(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('secure storage write failed (non-fatal, session will not survive refresh): $e');
    }
  }

  Future<void> _deleteTokens() async {
    try {
      await _storage.delete(key: _accessTokenKey);
      await _storage.delete(key: _refreshTokenKey);
    } catch (e) {
      debugPrint('secure storage delete failed (non-fatal): $e');
    }
  }

  // 액세스 토큰 만료(exp) 90초 전에 자동으로 리프레시 - 사용자가 뭔가 누르는 순간 하필
  // 토큰이 막 만료돼서 401 나는 경우를 미리 방지함. 화면들은 authState.accessToken을
  // 호출 시점에 그대로 읽기만 하면 되고 갱신 로직을 몰라도 됨
  void _scheduleRefresh(String accessToken) {
    _refreshTimer?.cancel();
    final exp = _jwtExpiry(accessToken);
    if (exp == null || _refreshToken == null) return;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    final delay = expiresAt.difference(DateTime.now().toUtc()) - const Duration(seconds: 90);
    _refreshTimer = Timer(delay.isNegative ? Duration.zero : delay, _refreshNow);
  }

  Future<void> _refreshNow() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return;
    try {
      final tokens = await _authService.refresh(refreshToken);
      _accessToken = tokens.accessToken;
      await _writeStorage(_accessTokenKey, tokens.accessToken);
      _scheduleRefresh(tokens.accessToken);
    } catch (e) {
      // 리프레시 토큰 자체가 만료/폐기됨 - 재로그인 필요. 다음 API 호출이 401로 실패하면서
      // 자연스럽게 사용자에게 드러나므로 여기서 강제로 로그아웃시키지 않고 조용히 둠
      debugPrint('token refresh failed (non-fatal): $e');
    }
  }

  // 앱 시작 시 저장된 토큰으로 세션 복구 시도. 액세스 토큰이 이미 만료됐으면 리프레시
  // 토큰으로 먼저 갱신을 시도하고, 그마저 없거나 실패하면 로그인 화면으로 남음
  Future<void> tryRestoreSession() async {
    final accessToken = await _readStorage(_accessTokenKey);
    final refreshToken = await _readStorage(_refreshTokenKey);
    if (accessToken == null) return;
    _accessToken = accessToken;
    _refreshToken = refreshToken;

    final exp = _jwtExpiry(accessToken);
    final isExpired = exp != null &&
        DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true).isBefore(DateTime.now().toUtc());
    if (isExpired && refreshToken != null) {
      await _refreshNow();
    } else {
      _scheduleRefresh(accessToken);
    }

    try {
      await _fetchProfile();
    } catch (_) {
      await _clearSession();
    }
  }

  Future<bool> signup({
    required String email,
    required String password,
    required String nickname,
    required String country,
  }) async {
    isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      await _authService.signup(
        email: email,
        password: password,
        nickname: nickname,
        country: country,
      );
      // 자동 로그인하지 않음 - 가입 후 로그인 화면으로 보내서 직접 로그인하게 함 (signup_screen.dart)
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      final tokens = await _authService.login(email: email, password: password);
      _accessToken = tokens.accessToken;
      _refreshToken = tokens.refreshToken;
      await _writeStorage(_accessTokenKey, tokens.accessToken);
      await _writeStorage(_refreshTokenKey, tokens.refreshToken);
      _scheduleRefresh(tokens.accessToken);
      await _fetchProfile();
      return true;
    } on ApiException catch (e) {
      lastError = e.message;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // Cognito Hosted UI OAuth 교환(social_auth_service.dart)까지 끝난 토큰 한 쌍을 일반
  // login()과 동일하게 처리 - 자동 갱신 스케줄도 그대로 태움
  Future<bool> completeSocialLogin({
    required String accessToken,
    required String refreshToken,
  }) async {
    isLoading = true;
    lastError = null;
    notifyListeners();
    try {
      _accessToken = accessToken;
      _refreshToken = refreshToken;
      final json = await _authService.completeSocialSession(accessToken);
      profile = UserProfile.fromJson(json);
      await _writeStorage(_accessTokenKey, accessToken);
      await _writeStorage(_refreshTokenKey, refreshToken);
      _scheduleRefresh(accessToken);
      unawaited(appState.loadMyLikes(accessToken));
      unawaited(_fetchAdminStatus());
      return true;
    } catch (e) {
      debugPrint('social login failed: $e');
      await _clearSession();
      lastError = 'Google 로그인 처리에 실패했어요.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  Future<void> _fetchProfile() async {
    final json = await _authService.me(_accessToken!);
    profile = UserProfile.fromJson(json);
    notifyListeners();
    // 로그인/세션 복구 시점에 좋아요 목록을 한 번에 받아와서 채워둠 -
    // 상품 카드마다 좋아요 여부를 개별 조회하지 않게 하는 핵심 장치
    unawaited(appState.loadMyLikes(_accessToken!));
    unawaited(_fetchAdminStatus());
  }

  // 실패해도(네트워크 오류 등) 관리자 페이지만 안 보이는 거지 로그인 자체를 막으면 안 되므로
  // 별도 함수로 분리해서 실패를 조용히 삼킴
  Future<void> _fetchAdminStatus() async {
    try {
      isAdmin = await _authService.isAdmin(_accessToken!);
      notifyListeners();
    } catch (e) {
      debugPrint('admin status check failed (non-fatal): $e');
      isAdmin = false;
    }
  }

  Future<void> _clearSession() async {
    _refreshTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    profile = null;
    isAdmin = false;
    appState.clearLikes();
    await _deleteTokens();
  }
}

final AuthState authState = AuthState();
