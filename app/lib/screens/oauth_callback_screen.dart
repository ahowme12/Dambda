import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/social_auth_service.dart';
import '../state/auth_state.dart';
import '../theme/app_theme.dart';

class OAuthCallbackScreen extends StatefulWidget {
  const OAuthCallbackScreen({super.key});

  @override
  State<OAuthCallbackScreen> createState() => _OAuthCallbackScreenState();
}

class _OAuthCallbackScreenState extends State<OAuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    try {
      final tokens = await SocialAuthService().exchangeCallback(Uri.base);
      final ok = await authState.completeSocialLogin(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
      if (!mounted) return;
      if (ok) {
        context.go('/');
      } else {
        setState(() => _error = authState.lastError);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text('Google 로그인 처리 중...'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('로그인 화면으로 돌아가기'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
