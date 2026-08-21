import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/language_picker.dart';

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _codeRequested = false;
  bool _loading = false;
  bool _obscurePassword = true;

  // dambda-sub 원본을 그대로 가져오면서 이 화면만 임시로 수동 스위치맵을 씀 - 나머지
  // 화면들처럼 AppLocalizations(.arb) 기반으로 옮기는 건 별도 작업으로 남겨둠(기능 우선)
  Map<String, String> get _text {
    final code = Localizations.localeOf(context).languageCode;
    return switch (code) {
      'en' => {
        'title': 'Reset password',
        'send': 'Send verification code',
        'sent': 'If the account exists, a verification code has been sent by email.',
        'code': 'Verification code',
        'newPassword': 'New password',
        'change': 'Change password',
        'success': 'Password changed. Please log in with the new password.',
        'error': 'The request failed. Please check the information and try again.',
      },
      'ja' => {
        'title': 'パスワード再設定',
        'send': '認証コードを送信',
        'sent': 'アカウントが存在する場合、メールで認証コードを送信しました。',
        'code': '認証コード',
        'newPassword': '新しいパスワード',
        'change': 'パスワードを変更',
        'success': 'パスワードを変更しました。新しいパスワードでログインしてください。',
        'error': '処理に失敗しました。入力内容を確認してください。',
      },
      'zh' => {
        'title': '重置密码',
        'send': '发送验证码',
        'sent': '如果账号存在，验证码已发送至邮箱。',
        'code': '验证码',
        'newPassword': '新密码',
        'change': '修改密码',
        'success': '密码已修改，请使用新密码登录。',
        'error': '请求失败，请检查输入信息后重试。',
      },
      _ => {
        'title': '비밀번호 재설정',
        'send': '인증 코드 받기',
        'sent': '가입된 계정이라면 이메일로 인증 코드를 보냈습니다.',
        'code': '인증 코드',
        'newPassword': '새 비밀번호',
        'change': '비밀번호 변경',
        'success': '비밀번호가 변경됐습니다. 새 비밀번호로 로그인해주세요.',
        'error': '요청에 실패했습니다. 입력 정보를 확인해주세요.',
      },
    };
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _authService.requestPasswordReset(email);
      if (!mounted) return;
      setState(() => _codeRequested = true);
      _message(_text['sent']!);
    } catch (_) {
      if (mounted) _message(_text['error']!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_codeController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      return;
    }
    setState(() => _loading = true);
    try {
      await _authService.confirmPasswordReset(
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        newPassword: _passwordController.text,
      );
      if (!mounted) return;
      _message(_text['success']!);
      context.go('/login');
    } on ApiException catch (e) {
      if (mounted) _message(e.message);
    } catch (_) {
      if (mounted) _message(_text['error']!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go('/login'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(_text['title']!),
        actions: [
          IconButton(
            icon: const Icon(Icons.language, color: AppColors.textPrimary),
            onPressed: () => showLanguagePicker(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                enabled: !_codeRequested,
                decoration: InputDecoration(
                  labelText: l10n.emailLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (!_codeRequested)
                ElevatedButton(
                  onPressed: _loading ? null : _requestCode,
                  child: Text(_text['send']!),
                )
              else ...[
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _text['code'],
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: _text['newPassword'],
                    helperText: l10n.passwordHelper,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loading ? null : _confirm,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_text['change']!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
