import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DambdaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget>? actions;

  const DambdaAppBar({super.key, this.actions});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 20,
      title: const Text(
        'DAMBDA',
        style: TextStyle(
          color: AppColors.primary,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
      actions: actions ??
          [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search, color: AppColors.textPrimary),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.notifications_none_rounded,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
          ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);
}
