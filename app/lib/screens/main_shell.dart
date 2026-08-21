import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    appState.loadProducts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showNotifications());
  }

  // 검열로 삭제된 내 게시물이 있으면 앱 진입 시 한 번 알려주고 읽음 처리함 - 매번 다시
  // 뜨지 않도록 다이얼로그를 닫는 즉시 서버에 읽음 표시를 남김(routes/notifications.js)
  Future<void> _showNotifications() async {
    final token = authState.accessToken;
    if (token == null) return;
    try {
      final notifications = await _notificationService.listUnread(token);
      if (!mounted || notifications.isEmpty) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('알림'),
          content: SizedBox(
            width: 420,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    notification['notificationMessage'] as String? ??
                        '해당 게시물은 관리자에 의해 삭제되었습니다.',
                  ),
                  subtitle: notification['productId'] == null
                      ? null
                      : Text('상품: ${notification['productId']}'),
                );
              },
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      await Future.wait(
        notifications.map(
          (notification) => _notificationService.markRead(token, notification['eventId'] as String),
        ),
      );
    } catch (error) {
      debugPrint('notification check failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final items = [
      (icon: Icons.home_rounded, outlineIcon: Icons.home_outlined, label: l10n.navHome),
      (icon: Icons.menu_rounded, outlineIcon: Icons.menu_rounded, label: l10n.navCategory),
      (icon: Icons.favorite, outlineIcon: Icons.favorite_border, label: l10n.navLikes),
      (icon: Icons.person, outlineIcon: Icons.person_outline, label: l10n.navMy),
    ];
    final currentIndex = widget.navigationShell.currentIndex;
    return Scaffold(
      body: widget.navigationShell,
      // 탭 4개(home/category/likes/my) 어디서든 뜨는 채팅 버블 - product_detail/chat 화면은
      // rootNavigatorKey로 이 Scaffold 위에 풀스크린으로 덮이므로 그쪽에서는 자동으로 안 보임
      floatingActionButton: FloatingActionButton(
        onPressed: () => openChat(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 60,
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => widget.navigationShell.goBranch(
                      i,
                      initialLocation: i == currentIndex,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == currentIndex ? items[i].icon : items[i].outlineIcon,
                          color: i == currentIndex
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == currentIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == currentIndex
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
