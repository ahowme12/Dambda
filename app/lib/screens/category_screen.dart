import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../router.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dambda_app_bar.dart';
import '../widgets/product_list_tile.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  static const _all = '__all__';
  String _selected = _all;

  String _categoryLabel(AppLocalizations l10n, String category) => switch (category) {
    'SNACK' => l10n.categorySnack,
    'COSMETIC' => l10n.categoryCosmetic,
    'LIVING' => l10n.categoryLiving,
    _ => category,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: const DambdaAppBar(),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final categories = [_all, ...{for (final p in appState.products) p.category}];
          final products = _selected == _all
              ? appState.products
              : appState.products.where((p) => p.category == _selected).toList();

          return Column(
            children: [
              SizedBox(
                height: 48,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final selected = category == _selected;
                    final label = category == _all
                        ? l10n.categoryAll
                        : _categoryLabel(l10n, category);
                    return GestureDetector(
                      onTap: () => setState(() => _selected = category),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.primary : AppColors.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _buildList(products)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildList(List<Product> products) {
    if (appState.productsLoading && appState.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (appState.productsError != null && appState.products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              appState.productsError!,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => appState.loadProducts(),
              child: Text(AppLocalizations.of(context)!.retryButton),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: products.length,
      separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
      itemBuilder: (context, index) {
        final product = products[index];
        return ProductListTile(
          product: product,
          onTap: () => openProductDetail(context, '/category', product.id),
        );
      },
    );
  }
}
