import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'screens/category_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/likes_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/my_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/signup_screen.dart';
import 'state/auth_state.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// 상품 상세는 홈/카테고리/좋아요 3개 탭에서 다 진입 가능해서 각 브랜치 하위에
// 동일한 라우트를 중첩시킴(go_router 공식 StatefulShellRoute 예제와 동일한 패턴).
// parentNavigatorKey: rootNavigatorKey로 지정해서 하단 네비 없이 풀스크린으로 뜸(기존 UX 유지).
//
// 알려진 한계: context.push()가 이 프로젝트의 Flutter/go_router 조합에서 브라우저 주소창을
// 갱신하지 않는 버그를 확인함(redirect/refreshListenable/셸 중첩 여부/parentNavigatorKey 유무/
// go_router 14.x·17.x 전부 테스트, 앱 코드와 무관한 최소 재현 케이스로도 재현됨). 그래서 웹에서만
// context.go()를 써서 주소창을 정상 갱신시키고(상세 페이지 새로고침이 같은 페이지를 유지),
// 네이티브(뒤로가기 버튼이 브라우저에 없는 플랫폼)에서는 계속 push()를 쓴다.
// go()는 Navigator 스택에 이전 페이지를 쌓지 않아 자동 AppBar 뒤로가기 버튼이 안 뜨므로,
// ProductDetailScreen이 직접 뒤로가기를 그린다(canPop이면 pop, 아니면 URL에서 부모 탭 경로를
// 역산해 go) - openProductDetail()/ProductDetailScreen 참고.
List<RouteBase> _productDetailRoutes() => [
  GoRoute(
    path: 'product/:id',
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
  ),
];

// 홈/카테고리/좋아요 3개 탭에서 공통으로 쓰는 상품 상세 진입 헬퍼.
// parentPath는 해당 탭의 최상위 경로('/', '/category', '/likes')
void openProductDetail(BuildContext context, String parentPath, String productId) {
  if (kIsWeb) {
    final path = parentPath == '/' ? '/product/$productId' : '$parentPath/product/$productId';
    context.go(path);
  } else {
    context.push('product/$productId');
  }
}

// 홈 탭에서만 진입하는 AI 채팅 화면 - 상품 상세와 같은 push/go 규칙
void openChat(BuildContext context) {
  if (kIsWeb) {
    context.go('/chat');
  } else {
    context.push('chat');
  }
}

final GoRouter router = GoRouter(
  navigatorKey: rootNavigatorKey,
  refreshListenable: authState,
  redirect: (context, state) {
    final loggedIn = authState.isLoggedIn;
    final onAuthPage =
        state.matchedLocation == '/login' || state.matchedLocation == '/signup';
    if (!loggedIn && !onAuthPage) return '/login';
    if (loggedIn && onAuthPage) return '/';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, state) => const SignupScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const HomeScreen(),
              routes: [
                ..._productDetailRoutes(),
                GoRoute(
                  path: 'chat',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => const ChatScreen(),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/category',
              builder: (context, state) => const CategoryScreen(),
              routes: _productDetailRoutes(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/likes',
              builder: (context, state) => const LikesScreen(),
              routes: _productDetailRoutes(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [GoRoute(path: '/my', builder: (context, state) => const MyScreen())],
        ),
      ],
    ),
  ],
);
