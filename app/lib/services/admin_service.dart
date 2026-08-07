import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

class AdminService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<List<Map<String, dynamic>>> listReviews(String token) async {
    final response = await http
        .get(_uri('/admin/reviews'), headers: {'Authorization': 'Bearer $token'})
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '관리자 권한이 없거나 리뷰를 불러오지 못했습니다.');
    }
    return ((jsonDecode(response.body) as Map<String, dynamic>)['reviews'] as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> deleteReview(String token, String userId, String productId) async {
    final response = await http
        .delete(
          _uri('/admin/reviews/${Uri.encodeComponent(userId)}/${Uri.encodeComponent(productId)}'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, '리뷰를 삭제하지 못했습니다.');
    }
  }

  Future<List<Map<String, dynamic>>> listModerationEvents(String token) async {
    final response = await http
        .get(_uri('/admin/moderation-events'), headers: {'Authorization': 'Bearer $token'})
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '검열 내역을 불러오지 못했습니다.');
    }
    return ((jsonDecode(response.body) as Map<String, dynamic>)['events'] as List)
        .cast<Map<String, dynamic>>();
  }

  String moderationImageUrl(String eventId) =>
      _uri('/admin/moderation-events/${Uri.encodeComponent(eventId)}/image').toString();

  Future<void> updateModerationStatus(String token, String eventId, String status) async {
    final response = await http
        .patch(
          _uri('/admin/moderation-events/${Uri.encodeComponent(eventId)}'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({'status': status}),
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '검열 상태를 변경하지 못했습니다.');
    }
  }

  Future<void> deleteModerationEvent(String token, String eventId) async {
    final response = await http
        .delete(
          _uri('/admin/moderation-events/${Uri.encodeComponent(eventId)}'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, '검열 내역을 삭제하지 못했습니다.');
    }
  }

  Future<void> addProduct({
    required String token,
    required Map<String, String> fields,
    required Uint8List imageBytes,
    required String imageName,
    required String mimeType,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/admin/products'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageName,
          contentType: _mediaType(mimeType),
        ),
      );
    final response = await http.Response.fromStream(
      await request.send().timeout(requestTimeout, onTimeout: timeoutError),
    );
    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, '상품을 등록하지 못했습니다.');
    }
  }

  Future<void> updateProduct({
    required String token,
    required String productId,
    required Map<String, String> fields,
    Uint8List? imageBytes,
    String? imageName,
    String? mimeType,
  }) async {
    final request = http.MultipartRequest('PUT', _uri('/admin/products/${Uri.encodeComponent(productId)}'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields.addAll(fields);
    if (imageBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: imageName ?? 'product.jpg',
          contentType: _mediaType(mimeType ?? 'image/jpeg'),
        ),
      );
    }
    final response = await http.Response.fromStream(
      await request.send().timeout(requestTimeout, onTimeout: timeoutError),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, '상품을 수정하지 못했습니다.');
    }
  }

  Future<void> deleteProduct(String token, String productId) async {
    final response = await http
        .delete(
          _uri('/admin/products/${Uri.encodeComponent(productId)}'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 204) {
      throw ApiException(response.statusCode, '상품을 삭제하지 못했습니다.');
    }
  }

  MediaType _mediaType(String value) {
    final parts = value.split('/');
    return MediaType(parts.first, parts.length > 1 ? parts[1] : 'jpeg');
  }
}
