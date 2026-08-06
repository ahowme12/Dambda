import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../models/product.dart';
import '../router.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/app_theme.dart';
import '../widgets/product_list_tile.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 상품 상세 화면과 동일한 뒤로가기 규칙(라우터 주석 참고) - go()로 진입했으면 Navigator
  // 스택이 비어있어서 canPop()이 false이므로 URL에서 "/chat" 접미사를 떼어 부모로 이동
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final location = GoRouterState.of(context).uri.toString();
    var parent = location.endsWith('/chat')
        ? location.substring(0, location.length - '/chat'.length)
        : '/';
    if (parent.isEmpty) parent = '/';
    context.go(parent);
  }

  void _send() {
    final text = _controller.text;
    _controller.clear();
    chatState.send(text, appState.products);
  }

  void _openProduct(Product product) {
    openProductDetail(context, '/', product.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBack(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 20, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(l10n.askAiFinderTitle),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: chatState,
        builder: (context, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          });

          return Column(
            children: [
              Expanded(
                child: chatState.messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            l10n.askAiFinderHint,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        itemCount: chatState.messages.length,
                        itemBuilder: (context, index) {
                          final message = chatState.messages[index];
                          return _ChatBubble(message: message, onProductTap: _openProduct);
                        },
                      ),
              ),
              if (chatState.sending)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          onSubmitted: (_) => chatState.sending ? null : _send(),
                          decoration: InputDecoration(
                            hintText: l10n.askAiFinderHint,
                            filled: true,
                            fillColor: AppColors.surface,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: chatState.sending ? null : _send,
                        icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final ValueChanged<Product> onProductTap;

  const _ChatBubble({required this.message, required this.onProductTap});

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isUser ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          for (final product in message.matches)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.surface),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ProductListTile(product: product, onTap: () => onProductTap(product)),
              ),
            ),
        ],
      ),
    );
  }
}
