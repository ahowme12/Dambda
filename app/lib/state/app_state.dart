import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/product_interactions_service.dart';
import '../services/product_service.dart';

class AppState extends ChangeNotifier {
  final ProductInteractionsService _interactions = ProductInteractionsService();
  final ProductService _productService = ProductService();

  List<Product> products = [];
  bool productsLoading = false;
  String? productsError;
  final Set<String> _likedIds = {};
  final Set<String> _pendingLikeIds = {};

  bool isLiked(String productId) => _likedIds.contains(productId);
  bool isLikePending(String productId) => _pendingLikeIds.contains(productId);

  Future<void> loadProducts() async {
    productsLoading = true;
    notifyListeners();
    try {
      products = await _productService.list();
      productsError = null;
    } catch (e) {
      productsError = e is ApiException ? e.message : '상품을 불러오지 못했어요.';
    } finally {
      productsLoading = false;
      notifyListeners();
    }
  }

  // 로그인 시점에 한 번에 좋아요 목록을 받아와서 채움 - 상품 카드마다 좋아요 여부를
  // 개별 조회하지 않게 하는 핵심 장치. 실패해도 조용히 무시 (좋아요 없이 시작할 뿐)
  Future<void> loadMyLikes(String token) async {
    try {
      final ids = await _interactions.myLikedProductIds(token);
      _likedIds
        ..clear()
        ..addAll(ids);
      notifyListeners();
    } catch (_) {
      // 무시 - 다음 로그인/새로고침 때 다시 시도됨
    }
  }

  void clearLikes() {
    _likedIds.clear();
    notifyListeners();
  }

  Future<void> toggleLike(String productId, String? token) async {
    if (token == null || _pendingLikeIds.contains(productId)) return;

    final wasLiked = _likedIds.contains(productId);
    // 낙관적 업데이트 - 즉시 반영하고 실패하면 롤백
    if (wasLiked) {
      _likedIds.remove(productId);
    } else {
      _likedIds.add(productId);
    }
    _pendingLikeIds.add(productId);
    notifyListeners();

    try {
      if (wasLiked) {
        await _interactions.unlike(token, productId);
      } else {
        await _interactions.like(token, productId);
      }
    } on ApiException catch (_) {
      // 롤백
      if (wasLiked) {
        _likedIds.add(productId);
      } else {
        _likedIds.remove(productId);
      }
    } finally {
      _pendingLikeIds.remove(productId);
      notifyListeners();
    }
  }

  List<Product> get likedProducts =>
      products.where((p) => _likedIds.contains(p.id)).toList();
}

final AppState appState = AppState();
