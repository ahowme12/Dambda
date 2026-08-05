import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'state/auth_state.dart';
import 'state/locale_state.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 웹에서 해시(#) 없는 깔끔한 URL을 쓰기 위함 - S3 정적 호스팅의 error_document가
  // index.html로 폴백하도록 이미 설정돼 있어서 별도 인프라 변경 없이도 새로고침이 동작함
  if (kIsWeb) usePathUrlStrategy();
  // 저장된 토큰이 있으면 재로그인 없이 세션 복구 시도 (네이티브 실행 시 기본 런치 스크린이
  // 이 짧은 대기 구간을 덮어줌)
  await authState.tryRestoreSession();
  await localeState.loadSaved();
  runApp(const DambdaApp());
}

class DambdaApp extends StatelessWidget {
  const DambdaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeState,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'DAMBDA',
          debugShowCheckedModeBanner: false,
          theme: appTheme,
          locale: localeState.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        );
      },
    );
  }
}
