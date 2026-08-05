import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import 'app_state.dart';

const _accessTokenKey = 'dambda_access_token';

class AuthState extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _accessToken;
  UserProfile? profile;
  bool isLoading = false;
  String? lastError;

  bool get isLoggedIn => _accessToken != null && profile != null;
  String? get accessToken => _accessToken;

  // flutter_secure_storage(웹)는 브라우저 Web Crypto API를 쓰는데 이게 HTTPS/localhost
  // 같은 "secure context"에서만 동작함. 지금 S3 정적 호스팅은 HTTP라 여기서 예외가 남 -
  // 로그인 자체(백엔드 호출)는 성공해도 토큰 저장이 실패하면서 화면이 조용히 멈추는 걸 방지하려고
  // 저장 실패를 로그인 성공/실패와 분리함 (HTTPS로 옮기면 자동으로 새로고침 후에도 로그인 유지됨)
  Future<String?> _readToken() async {
    try {
      return await _storage.read(key: _accessTokenKey);
    } catch (e) {
      debugPrint('secure storage read failed (non-fatal): $e');
      return null;
    }
  }

  Future<void> _writeToken(String token) async {
    try {
      await _storage.write(key: _accessTokenKey, value: token);
    } catch (e) {
      debugPrint('secure storage write failed (non-fatal, session will not survive refresh): $e');
    }
  }

  Future<void> _deleteToken() async {
    try {
      await _storage.delete(key: _accessTokenKey);
    } catch (e) {
      debugPrint('secure storage delete failed (non-fatal): $e');
    }
  }

  // 앱 시작 시 저장된 토큰으로 세션 복구 시도. 만료/무효면 그냥 로그인 화면으로 남음
  // (리프레시 토큰 플로우는 아직 없음 - 다음 단계에서 추가)
  Future<void> tryRestoreSession() async {
    final token = await _readToken();
    if (token == null) return;
    _accessToken = token;
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
      await _writeToken(tokens.accessToken);
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
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    profile = null;
    appState.clearLikes();
    await _deleteToken();
  }
}

final AuthState authState = AuthState();
