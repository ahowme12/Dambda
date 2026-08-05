import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config.dart';
import '../models/review.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

// 사진이 첨부되면 검열(Rekognition/Comprehend)까지 거치느라 일반 요청보다 오래 걸릴 수 있어서
// 좀 더 여유를 둠
const _uploadTimeout = Duration(seconds: 30);

class ReviewService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<ReviewsResult> list(String productId, {String? lang}) async {
    final uri = _uri('/products/$productId/reviews');
    final response = await http
        .get(lang == null ? uri : uri.replace(queryParameters: {'lang': lang}))
        .timeout(requestTimeout, onTimeout: timeoutError);
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return ReviewsResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Review> submit({
    required String token,
    required String productId,
    required int rating,
    required String text,
    List<int>? photoBytes,
    String? photoFilename,
    String? photoMimeType,
  }) async {
    final request = http.MultipartRequest('POST', _uri('/products/$productId/reviews'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['rating'] = rating.toString()
      ..fields['text'] = text;

    if (photoBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoFilename ?? 'photo.jpg',
          // 명시 안 하면 기본값이 application/octet-stream이 돼서 백엔드의
          // image/jpeg|png|webp 화이트리스트에 항상 걸려 거부당함 - 실제 형식을 넣어줘야 함
          contentType: MediaType.parse(photoMimeType ?? 'image/jpeg'),
        ),
      );
    }

    final streamedResponse =
        await request.send().timeout(_uploadTimeout, onTimeout: timeoutError);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return Review.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Review> update({
    required String token,
    required String productId,
    required int rating,
    required String text,
    List<int>? photoBytes,
    String? photoFilename,
    String? photoMimeType,
    bool removePhoto = false,
  }) async {
    final request = http.MultipartRequest('PUT', _uri('/products/$productId/reviews'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['rating'] = rating.toString()
      ..fields['text'] = text
      ..fields['removePhoto'] = removePhoto.toString();

    if (photoBytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoFilename ?? 'photo.jpg',
          contentType: MediaType.parse(photoMimeType ?? 'image/jpeg'),
        ),
      );
    }

    final streamedResponse =
        await request.send().timeout(_uploadTimeout, onTimeout: timeoutError);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    return Review.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> delete({required String token, required String productId}) async {
    final response = await http
        .delete(
          _uri('/products/$productId/reviews'),
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
      final reasons = body['reasons'] as List?;
      if (reasons != null && reasons.isNotEmpty) {
        return '리뷰가 정책에 위배되어 등록할 수 없어요. (${reasons.join(', ')})';
      }
      final error = body['error'] as String?;
      switch (error) {
        case 'already reviewed this product':
          return '이미 이 상품에 리뷰를 남기셨어요.';
        case 'file_too_large':
          return '사진 용량이 너무 커요 (5MB 이하로 올려주세요).';
        case 'invalid_file_type':
          return '지원하지 않는 사진 형식이에요.';
        case 'review not found':
          return '리뷰를 찾을 수 없어요.';
        default:
          return error ?? '요청에 실패했어요.';
      }
    } catch (_) {
      return '요청에 실패했어요.';
    }
  }
}
