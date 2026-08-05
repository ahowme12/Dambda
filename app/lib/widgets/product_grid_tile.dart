import 'package:flutter/material.dart';
import '../models/product.dart';
import '../theme/app_theme.dart';
import 'product_thumb.dart';

class ProductGridTile extends StatelessWidget {
  final Product product;
  final bool liked;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;

  const ProductGridTile({
    super.key,
    required this.product,
    required this.liked,
    required this.onTap,
    required this.onLikeTap,
  });

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ProductThumb(
                  product: product,
                  size: double.infinity,
                  radius: 10,
                ),
              ),
              Positioned(
                right: 6,
                bottom: 6,
                child: GestureDetector(
                  onTap: onLikeTap,
                  child: Icon(
                    liked ? Icons.favorite : Icons.favorite_border,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.nameFor(lang),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            product.priceLabel,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
