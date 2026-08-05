import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../state/locale_state.dart';
import '../theme/app_theme.dart';

// 언어 이름 자체는 현재 UI 언어와 무관하게 각 언어의 고유 표기로 고정 표시
const _languages = [
  ('ko', '한국어'),
  ('en', 'English'),
  ('ja', '日本語'),
  ('zh', '中文'),
];

Future<void> showLanguagePicker(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  await showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.languagePickerTitle,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            for (final (code, label) in _languages)
              ListTile(
                title: Text(label),
                trailing: localeState.locale?.languageCode == code
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () {
                  localeState.setLocale(Locale(code));
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      );
    },
  );
}
