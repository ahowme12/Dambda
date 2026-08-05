import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefsKey = 'app_locale';

class LocaleState extends ChangeNotifier {
  // null이면 기기 로케일을 따라가되 지원하지 않는 언어면 ko로 자동 폴백됨
  // (MaterialApp.locale이 null일 때의 기본 동작). 값이 있으면 사용자가 마이 화면에서
  // 명시적으로 고른 것.
  Locale? locale;

  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null) {
      locale = Locale(code);
      notifyListeners();
    }
  }

  Future<void> setLocale(Locale value) async {
    locale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value.languageCode);
  }
}

final LocaleState localeState = LocaleState();
