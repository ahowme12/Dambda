import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dambda/main.dart';
import 'package:dambda/screens/signup_screen.dart';
import 'package:dambda/state/locale_state.dart';

void main() {
  testWidgets('Shows the login screen when logged out', (WidgetTester tester) async {
    // 테스트 환경의 기본 로케일은 en이라 명시적으로 ko를 지정해야 아래 한국어 문자열 검증이 통과함
    localeState.locale = const Locale('ko');
    await tester.pumpWidget(const DambdaApp());

    expect(find.text('DAMBDA'), findsOneWidget);
    expect(find.text('아이디 (이메일)'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);

    await tester.tap(find.text('아직 계정이 없으신가요? 회원가입'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.text('닉네임'), findsOneWidget);
    expect(find.text('국가'), findsOneWidget);
  });
}
