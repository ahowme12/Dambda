import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../models/review.dart';
import '../services/auth_service.dart';
import '../services/product_qa_service.dart';
import '../services/review_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final ReviewService _reviewService = ReviewService();
  final ProductQaService _qaService = ProductQaService();
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _qaController = TextEditingController();

  ReviewsResult? _result;
  bool _loadingReviews = true;
  bool _submitting = false;
  int _rating = 0;
  Uint8List? _photoBytes;
  String? _photoName;
  String? _photoMimeType;

  bool _asking = false;
  String? _aiAnswer;

  bool _editing = false;
  String? _editingExistingPhotoUrl;
  bool _photoRemoved = false;

  bool _initialReviewsLoaded = false;

  @override
  void initState() {
    super.initState();
    // /product/:id로 직접 진입(딥링크, 새로고침)하면 MainShell을 안 거치므로
    // 거기서만 트리거되는 카탈로그 로드가 안 불릴 수 있어 여기서도 보장해줌
    if (appState.products.isEmpty && !appState.productsLoading) {
      appState.loadProducts();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Localizations.localeOf(context) 같은 InheritedWidget 조회는 initState()에서 하면
    // "called before initState() completed" 예외가 남 - 프레임워크가 안내하는 대로
    // didChangeDependencies()(initState 직후 자동 호출)에서 최초 1회만 로드
    if (!_initialReviewsLoaded) {
      _initialReviewsLoaded = true;
      _loadReviews();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _qaController.dispose();
    super.dispose();
  }

  Future<void> _askAi() async {
    final question = _qaController.text.trim();
    if (question.isEmpty) return;

    setState(() {
      _asking = true;
      _aiAnswer = null;
    });
    try {
      final answer = await _qaService.ask(widget.productId, question);
      if (mounted) setState(() => _aiAnswer = answer);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  // 웹에서는 상세 진입 시 push() 대신 go()를 써서(주소창 동기화를 위해) Navigator 스택에
  // 이전 페이지가 쌓이지 않으므로 canPop()이 false - 이땐 현재 URL에서 "/product/:id" 접미사를
  // 떼어내 원래 있던 탭(홈/카테고리/좋아요) 경로로 직접 이동한다.
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final location = GoRouterState.of(context).uri.toString();
    final suffix = '/product/${widget.productId}';
    var parent = location.endsWith(suffix)
        ? location.substring(0, location.length - suffix.length)
        : '/';
    if (parent.isEmpty) parent = '/';
    context.go(parent);
  }

  Future<void> _loadReviews() async {
    setState(() => _loadingReviews = true);
    try {
      final lang = Localizations.localeOf(context).languageCode;
      final result = await _reviewService.list(
        widget.productId,
        lang: lang,
        token: authState.accessToken,
      );
      if (mounted) setState(() => _result = result);
    } catch (_) {
      // 조회 실패 시 목록은 비워둔 채로 두고 조용히 넘어감(로딩 인디케이터만 꺼짐)
    } finally {
      if (mounted) setState(() => _loadingReviews = false);
    }
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _photoName = file.name;
      // 플랫폼에 따라 mimeType이 비어있을 수 있어서, 그럴 땐 파일 확장자로 추론
      _photoMimeType = file.mimeType ?? _mimeTypeFromName(file.name);
    });
  }

  String _mimeTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _removePhoto() {
    setState(() {
      if (_photoBytes != null) {
        // 새로 고른 사진을 취소한 것 - 편집 중이었다면 기존 사진이 다시 보이게 됨
        _photoBytes = null;
        _photoName = null;
        _photoMimeType = null;
      } else {
        // 기존 사진 자체를 제거하겠다는 뜻
        _photoRemoved = true;
      }
    });
  }

  void _resetForm() {
    _textController.clear();
    setState(() {
      _rating = 0;
      _photoBytes = null;
      _photoName = null;
      _photoMimeType = null;
      _editing = false;
      _editingExistingPhotoUrl = null;
      _photoRemoved = false;
    });
  }

  void _startEdit(Review review) {
    _textController.text = review.text;
    setState(() {
      _rating = review.rating;
      _editing = true;
      _editingExistingPhotoUrl = review.photoUrl;
      _photoRemoved = false;
      _photoBytes = null;
      _photoName = null;
      _photoMimeType = null;
    });
  }

  Future<void> _confirmDelete(Review review) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteReviewTitle),
        content: Text(l10n.deleteReviewContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete, style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final token = authState.accessToken;
    if (token == null) return;
    try {
      await _reviewService.delete(token: token, productId: widget.productId);
      if (_editing) _resetForm();
      await _loadReviews();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _submitReview() async {
    final token = authState.accessToken;
    if (token == null) return;
    if (_rating == 0 || _textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.reviewValidationError)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      if (_editing) {
        await _reviewService.update(
          token: token,
          productId: widget.productId,
          rating: _rating,
          text: _textController.text.trim(),
          photoBytes: _photoBytes,
          photoFilename: _photoName,
          photoMimeType: _photoMimeType,
          removePhoto: _photoRemoved,
        );
      } else {
        await _reviewService.submit(
          token: token,
          productId: widget.productId,
          rating: _rating,
          text: _textController.text.trim(),
          photoBytes: _photoBytes,
          photoFilename: _photoName,
          photoMimeType: _photoMimeType,
        );
      }
      _resetForm();
      await _loadReviews();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lang = Localizations.localeOf(context).languageCode;
    final myUserId = authState.profile?.userId;
    final hasReviewed = _result?.reviews.any((r) => r.userId == myUserId) ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(context),
        ),
        title: const Text(
          'DAMBDA',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListenableBuilder(
        listenable: appState,
        builder: (context, _) {
          final matches = appState.products.where((p) => p.id == widget.productId);
          final product = matches.isEmpty ? null : matches.first;
          if (product == null) {
            if (appState.productsLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: Text(l10n.productNotFound, style: const TextStyle(color: AppColors.textSecondary)),
            );
          }
          final liked = appState.isLiked(product.id);
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Center(
                child: ConstrainedBox(
                  // 모바일 폭에서는 화면에 꽉 차고(제약이 안 걸림), 웹의 넓은 브라우저
                  // 창에서는 정사각 이미지가 그만큼 커지는 걸 막기 위해 최대 폭을 제한함
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: product.imageUrl == null
                        ? Container(
                            color: AppColors.surface,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.shopping_bag_outlined,
                              size: 64,
                              color: AppColors.textSecondary,
                            ),
                          )
                        : Image.network(
                            product.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AppColors.surface,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.shopping_bag_outlined,
                                size: 64,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.nameFor(lang),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          if (product.reasonFor(lang) != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              product.reasonFor(lang)!,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                product.priceLabel,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                product.storeFor(lang),
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (product.discountInfoFor(lang) != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    product.discountInfoFor(lang)!,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                              if (_result != null && _result!.reviewCount > 0) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.star, size: 14, color: Colors.amber[700]),
                                const SizedBox(width: 2),
                                Text(
                                  '${_result!.averageRating.toStringAsFixed(1)} (${_result!.reviewCount})',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => appState.toggleLike(product.id, authState.accessToken),
                      icon: Icon(
                        liked ? Icons.favorite : Icons.favorite_border,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              _AskAiSection(
                controller: _qaController,
                answer: _aiAnswer,
                asking: _asking,
                onAsk: _askAi,
              ),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  l10n.reviewCountLabel(_result?.reviewCount ?? 0),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingReviews)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                for (final review in _result?.reviews ?? [])
                  _ReviewTile(
                    review: review,
                    isMine: myUserId != null && review.userId == myUserId,
                    onEdit: () => _startEdit(review),
                    onDelete: () => _confirmDelete(review),
                  ),
                if ((_result?.reviews ?? []).isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      l10n.reviewsEmpty,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
              ],
              if ((!hasReviewed || _editing) && authState.accessToken != null) ...[
                const Divider(height: 32),
                _ReviewForm(
                  rating: _rating,
                  textController: _textController,
                  photoBytes: _photoBytes,
                  existingPhotoUrl: _editingExistingPhotoUrl,
                  photoRemoved: _photoRemoved,
                  isEditing: _editing,
                  submitting: _submitting,
                  onRatingChanged: (value) => setState(() => _rating = value),
                  onPickPhoto: _pickPhoto,
                  onRemovePhoto: _removePhoto,
                  onSubmit: _submitReview,
                  onCancel: _editing ? _resetForm : null,
                ),
              ],
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

class _AskAiSection extends StatelessWidget {
  final TextEditingController controller;
  final String? answer;
  final bool asking;
  final VoidCallback onAsk;

  const _AskAiSection({
    required this.controller,
    required this.answer,
    required this.asking,
    required this.onAsk,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                l10n.askAiTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => asking ? null : onAsk(),
                  decoration: InputDecoration(
                    hintText: l10n.askAiHint,
                    filled: true,
                    fillColor: AppColors.surface,
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
                  onPressed: asking ? null : onAsk,
                  child: asking
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
          if (answer != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(answer!, style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final Review review;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ReviewTile({
    required this.review,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.surface,
            child: Icon(Icons.person, size: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      review.authorNickname,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    _StarRow(rating: review.rating, size: 12),
                    if (review.isPending) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.reviewPending,
                          style: const TextStyle(fontSize: 10, color: AppColors.primary),
                        ),
                      ),
                    ],
                    // 검열에 걸려 비공개 처리된 리뷰 - 작성자 본인에게는 그대로 보이므로
                    // "검토 중"과는 다른 색으로 확실히 구분해서 정상 게시로 착각하지 않게 함
                    if (review.isBlocked) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.reviewBlocked,
                          style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                    if (isMine) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: onEdit,
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: onDelete,
                        child: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(review.text, style: const TextStyle(fontSize: 14)),
                if (review.photoUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      review.photoUrl!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  final int rating;
  final double size;

  const _StarRow({required this.rating, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star : Icons.star_border,
            size: size,
            color: Colors.amber[700],
          ),
      ],
    );
  }
}

class _ReviewForm extends StatelessWidget {
  final int rating;
  final TextEditingController textController;
  final Uint8List? photoBytes;
  final String? existingPhotoUrl;
  final bool photoRemoved;
  final bool isEditing;
  final bool submitting;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onPickPhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onSubmit;
  final VoidCallback? onCancel;

  const _ReviewForm({
    required this.rating,
    required this.textController,
    required this.photoBytes,
    required this.existingPhotoUrl,
    required this.photoRemoved,
    required this.isEditing,
    required this.submitting,
    required this.onRatingChanged,
    required this.onPickPhoto,
    required this.onRemovePhoto,
    required this.onSubmit,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showingExistingPhoto =
        photoBytes == null && existingPhotoUrl != null && !photoRemoved;
    final hasPhotoPreview = photoBytes != null || showingExistingPhoto;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isEditing ? l10n.reviewFormTitleEdit : l10n.reviewFormTitleNew,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              if (isEditing && onCancel != null) ...[
                const Spacer(),
                TextButton(
                  onPressed: onCancel,
                  child: Text(l10n.cancel, style: const TextStyle(color: AppColors.textSecondary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                GestureDetector(
                  onTap: () => onRatingChanged(i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      i <= rating ? Icons.star : Icons.star_border,
                      size: 32,
                      color: Colors.amber[700],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l10n.reviewHint,
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (hasPhotoPreview)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoBytes != null
                      ? Image.memory(photoBytes!, width: 80, height: 80, fit: BoxFit.cover)
                      : Image.network(
                          existingPhotoUrl!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                ),
                Positioned(
                  right: -8,
                  top: -8,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: AppColors.textSecondary),
                    onPressed: onRemovePhoto,
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: onPickPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(l10n.attachPhoto),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: submitting ? null : onSubmit,
              child: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isEditing ? l10n.updateReview : l10n.submitReview),
            ),
          ),
        ],
      ),
    );
  }
}
