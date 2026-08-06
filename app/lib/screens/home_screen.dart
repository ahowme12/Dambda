import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../router.dart';
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

// 인라인 검색창이 아니라 전용 채팅 화면(ChatScreen)으로 진입하는 배너 - 대화 상태는
// state/chat_state.dart의 전역 싱글턴(chatState)이 들고 있어서 이 화면을 나갔다 와도 안 끊김
class _AiFinderSection extends StatelessWidget {
  const _AiFinderSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => openChat(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.askAiFinderTitle,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.askAiFinderHint,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
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
