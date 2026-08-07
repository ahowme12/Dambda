import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../models/product.dart';
import '../services/admin_service.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  final _service = AdminService();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _store = TextEditingController();
  final _reason = TextEditingController();
  final _discount = TextEditingController();
  late final TabController _tabs;
  String _category = 'SNACK';
  XFile? _image;
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _moderationEvents = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    appState.loadProducts();
    _loadReviews();
    _loadModerationEvents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final controller in [_name, _price, _store, _reason, _discount]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadReviews() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _reviews = await _service.listReviews(authState.accessToken!);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadModerationEvents() async {
    try {
      final events = await _service.listModerationEvents(authState.accessToken!);
      if (mounted) setState(() => _moderationEvents = events);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _deleteReview(Map<String, dynamic> review) async {
    await _service.deleteReview(
      authState.accessToken!,
      review['userId'] as String,
      review['productId'] as String,
    );
    await _loadReviews();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (image != null && mounted) setState(() => _image = image);
  }

  Future<void> _addProduct() async {
    if (_image == null || [_name, _price, _store, _reason].any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('필수 항목과 이미지를 모두 입력해주세요.')));
      return;
    }
    setState(() => _loading = true);
    try {
      await _service.addProduct(
        token: authState.accessToken!,
        fields: {
          'name': _name.text.trim(),
          'price': _price.text.trim(),
          'category': _category,
          'store': _store.text.trim(),
          'reason': _reason.text.trim(),
          if (_discount.text.trim().isNotEmpty) 'discountInfo': _discount.text.trim(),
        },
        imageBytes: await _image!.readAsBytes(),
        imageName: _image!.name,
        mimeType: _image!.mimeType ?? 'image/jpeg',
      );
      await appState.loadProducts();
      if (!mounted) return;
      for (final controller in [_name, _price, _store, _reason, _discount]) {
        controller.clear();
      }
      setState(() => _image = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상품이 등록되었습니다.')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/my'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('관리자 페이지'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '리뷰 관리'),
            Tab(text: '검열 내역'),
            Tab(text: '상품 추가'),
            Tab(text: '상품 관리'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_reviewsTab(), _moderationTab(), _productTab(), _productsTab()],
      ),
    );
  }

  Widget _reviewsTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_reviews.isEmpty) return const Center(child: Text('등록된 리뷰가 없습니다.'));
    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _reviews.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final review = _reviews[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${review['authorNickname'] ?? review['userId']} · ★${review['rating']}'),
            subtitle: Text(
              '${review['text']}\n상품: ${review['productId']}'
              '${review['moderationStatus'] != null ? ' · ${review['moderationStatus']}' : ''}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: '리뷰 삭제',
              icon: const Icon(Icons.delete_outline, color: AppColors.primary),
              onPressed: () => _deleteReview(review),
            ),
          );
        },
      ),
    );
  }

  Widget _moderationTab() {
    if (_moderationEvents.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadModerationEvents,
        child: ListView(
          children: const [SizedBox(height: 180), Center(child: Text('차단된 검열 내역이 없습니다.'))],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadModerationEvents,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _moderationEvents.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final event = _moderationEvents[index];
          final comprehendScores = (event['comprehendScores'] as List? ?? const []);
          final rekognitionLabels = (event['rekognitionLabels'] as List? ?? const []);
          final reasons = (event['blockReasons'] as List? ?? const []).join(', ');
          final hasImage = event['quarantinePhotoKey'] != null &&
              (event['quarantinePhotoKey'] as String).isNotEmpty;
          final eventId = event['eventId'] as String;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Chip(label: Text('${event['status'] ?? 'PENDING'}')),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${event['userId']} · 상품 ${event['productId']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText('${event['reviewText'] ?? ''}'),
                  const SizedBox(height: 8),
                  Text('차단 사유: ${reasons.isEmpty ? '검열 서비스 오류' : reasons}'),
                  for (final label in comprehendScores)
                    Text(
                      '텍스트 · ${label['Name']} · ${_confidence(label['Score'])}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  for (final label in rekognitionLabels)
                    Text(
                      '이미지 · ${label['Name']} · ${_confidence(label['Confidence'])}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  if (hasImage) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        _service.moderationImageUrl(eventId),
                        headers: {'Authorization': 'Bearer ${authState.accessToken!}'},
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Text('격리 이미지를 불러오지 못했습니다.'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _reviewModerationEvent(eventId),
                        child: const Text('확인 완료'),
                      ),
                      TextButton(
                        onPressed: () => _deleteModerationEvent(eventId),
                        child: const Text('삭제'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _confidence(dynamic value) {
    final score = value is num ? value.toDouble() : 0;
    final percent = score <= 1 ? score * 100 : score;
    return '${percent.toStringAsFixed(1)}%';
  }

  Future<void> _reviewModerationEvent(String eventId) async {
    await _service.updateModerationStatus(authState.accessToken!, eventId, 'REVIEWED');
    await _loadModerationEvents();
  }

  Future<void> _deleteModerationEvent(String eventId) async {
    await _service.deleteModerationEvent(authState.accessToken!, eventId);
    await _loadModerationEvents();
  }

  Widget _productTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _field(_name, '상품명'),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: '카테고리', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'SNACK', child: Text('스낵')),
            DropdownMenuItem(value: 'COSMETIC', child: Text('화장품')),
            DropdownMenuItem(value: 'LIVING', child: Text('생활용품')),
          ],
          onChanged: (value) => setState(() => _category = value!),
        ),
        const SizedBox(height: 12),
        _field(_price, '가격(원)', keyboardType: TextInputType.number),
        _field(_store, '파는 곳'),
        _field(_reason, '상세 설명', maxLines: 3),
        _field(_discount, '할인 정보(선택)'),
        OutlinedButton.icon(
          onPressed: _pickImage,
          icon: const Icon(Icons.image_outlined),
          label: Text(_image?.name ?? '상품 이미지 선택'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading ? null : _addProduct,
          child: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('상품 등록'),
        ),
      ],
    );
  }

  Widget _productsTab() {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        if (appState.productsLoading && appState.products.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (appState.productsError != null && appState.products.isEmpty) {
          return Center(
            child: TextButton(
              onPressed: appState.loadProducts,
              child: const Text('상품을 불러오지 못했습니다. 다시 시도'),
            ),
          );
        }
        if (appState.products.isEmpty) {
          return const Center(child: Text('등록된 상품이 없습니다.'));
        }
        return RefreshIndicator(
          onRefresh: appState.loadProducts,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: appState.products.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final product = appState.products[index];
              return ListTile(
                leading: product.imageUrl == null
                    ? const Icon(Icons.inventory_2_outlined)
                    : Image.network(product.imageUrl!, width: 56, height: 56, fit: BoxFit.cover),
                title: Text(product.name),
                subtitle: Text('${product.category} · ${product.priceLabel}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '수정',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _editProduct(product),
                    ),
                    IconButton(
                      tooltip: '삭제',
                      icon: const Icon(Icons.delete_outline, color: AppColors.primary),
                      onPressed: () => _deleteProduct(product),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('상품 삭제'),
        content: Text('${product.name} 상품을 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await _service.deleteProduct(authState.accessToken!, product.id);
      await appState.loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상품을 삭제했습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editProduct(Product product) async {
    final name = TextEditingController(text: product.name);
    final price = TextEditingController(text: product.price.toString());
    final store = TextEditingController(text: product.store);
    final reason = TextEditingController(text: product.reason ?? '');
    final discount = TextEditingController(text: product.discountInfo ?? '');
    var category = product.category;
    XFile? replacementImage;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('상품 수정'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(name, '상품명'),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: '카테고리', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'SNACK', child: Text('간식')),
                      DropdownMenuItem(value: 'COSMETIC', child: Text('화장품')),
                      DropdownMenuItem(value: 'LIVING', child: Text('생활용품')),
                    ],
                    onChanged: (value) => setDialogState(() => category = value!),
                  ),
                  const SizedBox(height: 12),
                  _field(price, '가격', keyboardType: TextInputType.number),
                  _field(store, '파는 곳'),
                  _field(reason, '상세 설명', maxLines: 3),
                  _field(discount, '할인 정보(선택)'),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.image_outlined),
                    label: Text(replacementImage?.name ?? '이미지 교체(선택)'),
                    onPressed: () async {
                      final picked =
                          await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
                      if (picked != null) setDialogState(() => replacementImage = picked);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('저장')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() => _loading = true);
      try {
        await _service.updateProduct(
          token: authState.accessToken!,
          productId: product.id,
          fields: {
            'name': name.text.trim(),
            'price': price.text.trim(),
            'category': category,
            'store': store.text.trim(),
            'reason': reason.text.trim(),
            if (discount.text.trim().isNotEmpty) 'discountInfo': discount.text.trim(),
          },
          imageBytes: await replacementImage?.readAsBytes(),
          imageName: replacementImage?.name,
          mimeType: replacementImage?.mimeType,
        );
        await appState.loadProducts();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상품을 수정했습니다.')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    name.dispose();
    price.dispose();
    store.dispose();
    reason.dispose();
    discount.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}
