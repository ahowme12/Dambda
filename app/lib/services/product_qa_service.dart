import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'api_exception.dart';
import 'http_timeout.dart';

// LLM 추론(+ 도구 호출로 웹검색까지 하면 최대 3라운드)이라 일반 CRUD 요청보다
// 오래 걸릴 수 있어서 공통 타임아웃보다 여유를 둠
const _askTimeout = Duration(seconds: 45);

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

  Future<ProductRecommendation> findProducts(
    String query, {
    List<ChatTurn> history = const [],
  }) async {
    final response = await http
        .post(
          _uri('/products/recommend'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'query': query,
            'history': history.map((h) => h.toJson()).toList(),
          }),
        )
        .timeout(_askTimeout, onTimeout: timeoutError);

    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, _errorMessage(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return ProductRecommendation(
      answer: body['answer'] as String,
      productIds: (body['productIds'] as List).cast<String>(),
    );
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'] as String?;
      switch (error) {
        case 'question is required':
          return '질문을 입력해주세요.';
        case 'query is required':
          return '찾고 싶은 걸 입력해주세요.';
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

class ProductRecommendation {
  final String answer;
  final List<String> productIds;

  const ProductRecommendation({required this.answer, required this.productIds});
}

// Bedrock Converse API 형식과 맞춘 role('user'|'assistant') - 서버가 대화를 저장하지 않으므로
// 클라이언트(ChatState)가 들고 있다가 매 요청마다 그대로 다시 보냄
class ChatTurn {
  final String role;
  final String text;

  const ChatTurn({required this.role, required this.text});

  Map<String, String> toJson() => {'role': role, 'text': text};
}
