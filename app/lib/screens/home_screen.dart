import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../router.dart';
import '../services/api_exception.dart';
import '../services/product_qa_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/dambda_app_bar.dart';
import '../widgets/product_list_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _openDetail(BuildContext context, Product product) {
    openProductDetail(context, '/', product.id);
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
                return Column(
                  children: const [
                    // 모바일 앱은 웹에서만 안내(웹 배포 산출물에 같이 올라가는 APK를 내려받는 링크라
                    // 앱 안에서 또 이걸 보여줄 이유가 없음)
                    if (kIsWeb) _DownloadAppBanner(),
                    _AiFinderSection(),
                    _RecommendationBanner(),
                  ],
                );
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

class _AiFinderSection extends StatefulWidget {
  const _AiFinderSection();

  @override
  State<_AiFinderSection> createState() => _AiFinderSectionState();
}

class _AiFinderSectionState extends State<_AiFinderSection> {
  final ProductQaService _qaService = ProductQaService();
  final TextEditingController _controller = TextEditingController();

  bool _searching = false;
  String? _answer;
  List<Product> _matches = const [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _answer = null;
      _matches = const [];
    });
    try {
      final result = await _qaService.findProducts(query);
      final byId = {for (final p in appState.products) p.id: p};
      if (mounted) {
        setState(() {
          _answer = result.answer;
          _matches = result.productIds.map((id) => byId[id]).whereType<Product>().toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openMatch(Product product) {
    openProductDetail(context, '/', product.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                l10n.askAiFinderTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onSubmitted: (_) => _searching ? null : _search(),
                  decoration: InputDecoration(
                    hintText: l10n.askAiFinderHint,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _searching ? null : _search,
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(l10n.askAiButton),
                ),
              ),
            ],
          ),
          if (_answer != null) ...[
            const SizedBox(height: 12),
            Text(_answer!, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          for (final product in _matches)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: ProductListTile(product: product, onTap: () => _openMatch(product)),
              ),
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

class _DownloadAppBanner extends StatelessWidget {
  const _DownloadAppBanner();

  // 웹 빌드와 같은 S3 버킷에 함께 올라가는 APK - 상대 경로라 어느 도메인으로
  // 접속하든(서울/us-east-1) 알아서 같은 origin에서 받아짐
  static const _apkPath = '/downloads/dambda.apk';

  Future<void> _download() async {
    await launchUrl(Uri.parse(_apkPath), webOnlyWindowName: '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.24)),
      ),
      child: Row(
        children: [
          const Text('📱', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.downloadAppTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.downloadAppSubtitle,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _download,
            child: Text(l10n.downloadAppButton),
          ),
        ],
      ),
    );
  }
}
