import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../router.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dambda_app_bar.dart';
import '../widgets/product_grid_tile.dart';

class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DambdaAppBar(),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final liked = appState.likedProducts;
          if (liked.isEmpty) {
            return const _EmptyLikes();
          }
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: liked.length,
            itemBuilder: (context, index) {
              final product = liked[index];
              return ProductGridTile(
                product: product,
                liked: true,
                onTap: () => openProductDetail(context, '/likes', product.id),
                onLikeTap: () => appState.toggleLike(product.id, authState.accessToken),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyLikes extends StatelessWidget {
  const _EmptyLikes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🤍', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.likesEmpty,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
