import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/api_exception.dart';
import '../services/product_qa_service.dart';

class ChatMessage {
  final bool fromUser;
  final String text;
  final List<Product> matches;

  const ChatMessage({required this.fromUser, required this.text, this.matches = const []});
}

// appState/authState와 같은 패턴의 전역 싱글턴 - ChatScreen의 로컬 State가 아니라 여기 두는 게
// 핵심임. 화면(위젯)이 다시 만들어져도(다른 탭/상품 상세로 갔다 오는 것) 이 객체 자체는
// 앱이 켜있는 동안 계속 살아있어서 대화가 안 끊김. 새로고침(전체 리로드)까지는 못 버팀 -
// 서버에 세션을 저장하지 않는 무상태 구조라 브라우저를 새로고침하면 히스토리가 사라짐
class ChatState extends ChangeNotifier {
  final ProductQaService _qaService = ProductQaService();

  final List<ChatMessage> messages = [];
  bool sending = false;

  Future<void> send(String text, List<Product> catalog) async {
    final question = text.trim();
    if (question.isEmpty || sending) return;

    final history = messages
        .map((m) => ChatTurn(role: m.fromUser ? 'user' : 'assistant', text: m.text))
        .toList();

    messages.add(ChatMessage(fromUser: true, text: question));
    sending = true;
    notifyListeners();

    try {
      final result = await _qaService.findProducts(question, history: history);
      final byId = {for (final p in catalog) p.id: p};
      final matches = result.productIds.map((id) => byId[id]).whereType<Product>().toList();
      messages.add(ChatMessage(fromUser: false, text: result.answer, matches: matches));
    } on ApiException catch (e) {
      messages.add(ChatMessage(fromUser: false, text: e.message));
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void clear() {
    messages.clear();
    notifyListeners();
  }
}

final ChatState chatState = ChatState();
