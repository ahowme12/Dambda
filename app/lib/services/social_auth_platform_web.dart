import 'package:web/web.dart' as web;

String? readSocialSession(String key) => web.window.sessionStorage.getItem(key);
void writeSocialSession(String key, String value) =>
    web.window.sessionStorage.setItem(key, value);
void clearSocialSession(String key) => web.window.sessionStorage.removeItem(key);
void redirectToSocialLogin(String url) => web.window.location.assign(url);
