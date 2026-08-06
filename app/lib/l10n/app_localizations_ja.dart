// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get navHome => 'ホーム';

  @override
  String get navCategory => 'カテゴリー';

  @override
  String get navLikes => 'いいね';

  @override
  String get navMy => 'マイページ';

  @override
  String get emailLabel => 'ID（メール）';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get loginButton => 'ログイン';

  @override
  String get loginFailedDefault => 'ログインに失敗しました。';

  @override
  String get noAccountSignupPrompt => 'アカウントをお持ちでない方はこちら 会員登録';

  @override
  String get signupTitle => '会員登録';

  @override
  String get nicknameLabel => 'ニックネーム';

  @override
  String get countryLabel => '国';

  @override
  String get passwordHelper => '8文字以上、大文字・小文字と数字を含めてください。';

  @override
  String get countryRequiredError => '国を選択してください。';

  @override
  String get signupFailedDefault => '会員登録に失敗しました。';

  @override
  String get signupButton => '登録する';

  @override
  String get retryButton => '再試行';

  @override
  String get productNotFound => '商品が見つかりません。';

  @override
  String get homeBannerTitle => '韓国に来たなら、これは絶対に持ち帰って';

  @override
  String get homeBannerSubtitle => '旅行者が認めたお菓子とお土産';

  @override
  String get downloadAppTitle => 'Androidアプリでもっと便利に';

  @override
  String get downloadAppSubtitle => 'APKファイルをダウンロードしてインストール';

  @override
  String get downloadAppButton => 'ダウンロード';

  @override
  String get categoryAll => 'すべて';

  @override
  String get categorySnack => 'スナック';

  @override
  String get categoryCosmetic => '化粧品';

  @override
  String get categoryLiving => '生活用品';

  @override
  String get likesEmpty => 'まだいいねしたアイテムがありません';

  @override
  String get guestName => 'ゲスト旅行者';

  @override
  String get guestSubtitle => '見てまわった商品をダムダで整理してみましょう';

  @override
  String get statLikes => 'いいね';

  @override
  String get statBrowsed => '見たアイテム';

  @override
  String get menuLanguage => '言語設定';

  @override
  String get menuOrders => '注文履歴';

  @override
  String get menuSupport => 'カスタマーセンター';

  @override
  String get menuAbout => 'アプリ情報';

  @override
  String get menuLogout => 'ログアウト';

  @override
  String get languagePickerTitle => '言語選択';

  @override
  String reviewCountLabel(int count) {
    return 'レビュー $count件';
  }

  @override
  String get reviewsEmpty => 'まだレビューがありません。最初のレビューを書いてみましょう！';

  @override
  String get deleteReviewTitle => 'レビュー削除';

  @override
  String get deleteReviewContent => '本当に削除しますか？元に戻せません。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get delete => '削除';

  @override
  String get reviewValidationError => '星評価とレビュー内容をすべて入力してください。';

  @override
  String get reviewFormTitleNew => 'レビューを書く';

  @override
  String get reviewFormTitleEdit => 'レビューを編集';

  @override
  String get reviewHint => 'この商品はいかがでしたか？';

  @override
  String get attachPhoto => '写真を添付（任意）';

  @override
  String get submitReview => 'レビューを投稿';

  @override
  String get askAiTitle => 'AIに質問する';

  @override
  String get askAiHint => 'この商品について気になることを聞いてみましょう';

  @override
  String get askAiButton => '質問する';

  @override
  String get askAiFinderTitle => 'AIで探す';

  @override
  String get askAiFinderHint => '欲しいものを説明すると商品を探してくれます';

  @override
  String get updateReview => 'レビューを修正';
}
