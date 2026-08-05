import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/product.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

class ProductService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<List<Product>> list() async {
    final response = await http
        .get(_uri('/products'))
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '상품을 불러오지 못했어요.');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items = body['products'] as List;
    return items.map((json) => Product.fromJson(json as Map<String, dynamic>)).toList();
  }
}
