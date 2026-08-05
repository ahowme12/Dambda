import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';

class ProductThumb extends StatelessWidget {
  final Product product;
  final double size;
  final double radius;

  const ProductThumb({
    super.key,
    required this.product,
    this.size = 84,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = product.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl == null
            ? const _ThumbFallback()
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const _ThumbFallback(),
              ),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.shopping_bag_outlined, color: AppColors.textSecondary),
    );
  }
}
