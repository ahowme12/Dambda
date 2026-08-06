import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

// LLM 추론이라 일반 CRUD 요청보다 오래 걸릴 수 있어서 공통 타임아웃보다 여유를 둠
const _askTimeout = Duration(seconds: 30);

class ProductQaService {
  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<String> ask(String productId, String question) async {
    final response = await http
        .post(
          _uri('/products/$productId/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question}),
        )
        .timeout(_askTimeout, onTimeout: timeoutError);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['answer'] as String;
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as String?;
      switch (error) {
        case 'question is required':
          return '질문을 입력해주세요.';
        case 'product not found':
          return '상품 정보를 찾을 수 없어요.';
        default:
          return error ?? 'AI 답변을 받아오지 못했어요.';
      }
    } catch (_) {
      return 'AI 답변을 받아오지 못했어요.';
    }
  }
}
