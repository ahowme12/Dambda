import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dambda_app_bar.dart';
import '../widgets/product_list_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openDetail(BuildContext context, Product product) {
    context.push('product/${product.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const DambdaAppBar(),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          if (appState.productsLoading && appState.products.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (appState.productsError != null && appState.products.isEmpty) {
            return _ProductsError(
              message: appState.productsError!,
              retryLabel: AppLocalizations.of(context)!.retryButton,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: appState.products.length + 1,
            separatorBuilder: (context, index) {
              if (index == 0) return const SizedBox.shrink();
              return const Divider(indent: 20, endIndent: 20);
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                return const _RecommendationBanner();
              }
              final product = appState.products[index - 1];
              return ProductListTile(
                product: product,
                onTap: () => _openDetail(context, product),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProductsError extends StatelessWidget {
  final String message;
  final String retryLabel;

  const _ProductsError({required this.message, required this.retryLabel});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => appState.loadProducts(),
            child: Text(retryLabel),
          ),
        ],
      ),
    );
  }
}

class _RecommendationBanner extends StatelessWidget {
  const _RecommendationBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Text('🧳', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.homeBannerTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.homeBannerSubtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
