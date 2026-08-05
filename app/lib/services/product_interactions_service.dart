import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

class ProductInteractionsService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<List<String>> myLikedProductIds(String token) async {
    final response = await http
        .get(
          _uri('/products/likes/mine'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return (json['productIds'] as List).cast<String>();
  }

  Future<void> like(String token, String productId) async {
    final response = await http
        .put(
          _uri('/products/$productId/like'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
  }

  Future<void> unlike(String token, String productId) async {
    final response = await http
        .delete(
          _uri('/products/$productId/like'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error'] as String? ?? '요청에 실패했어요.';
    } catch (_) {
      return '요청에 실패했어요.';
    }
  }
}
