import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

class MainShell extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    appState.loadProducts();
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
