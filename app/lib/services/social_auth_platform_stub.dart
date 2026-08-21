String? readSocialSession(String key) => null;
void writeSocialSession(String key, String value) {}
void clearSocialSession(String key) {}

void redirectToSocialLogin(String url) {
  throw UnsupportedError('Social login is not configured for this platform.');
}
