import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'screens/category_screen.dart';
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
// go_router 14.x·17.x 전부 테스트, 앱 코드와 무관한 최소 재현 케이스로도 재현됨 - context.go()는
// 정상 동작하지만 그러면 AppBar 뒤로가기 버튼이 깨짐). push는 화면 전환과 뒤로가기 버튼은
// 정상 동작하므로(웹/네이티브 공통), 그걸 우선하고 주소창 동기화는 포기한 상태.
List<RouteBase> _productDetailRoutes() => [
  GoRoute(
    path: 'product/:id',
    parentNavigatorKey: rootNavigatorKey,
    builder: (context, state) => ProductDetailScreen(productId: state.pathParameters['id']!),
  ),
];

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
              routes: _productDetailRoutes(),
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
