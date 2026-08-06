import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
  ];

  /// No description provided for @navHome.
  ///
  /// In ko, this message translates to:
  /// **'홈'**
  String get navHome;

  /// No description provided for @navCategory.
  ///
  /// In ko, this message translates to:
  /// **'카테고리'**
  String get navCategory;

  /// No description provided for @navLikes.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get navLikes;

  /// No description provided for @navMy.
  ///
  /// In ko, this message translates to:
  /// **'마이'**
  String get navMy;

  /// No description provided for @emailLabel.
  ///
  /// In ko, this message translates to:
  /// **'아이디 (이메일)'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In ko, this message translates to:
  /// **'비밀번호'**
  String get passwordLabel;

  /// No description provided for @loginButton.
  ///
  /// In ko, this message translates to:
  /// **'로그인'**
  String get loginButton;

  /// No description provided for @loginFailedDefault.
  ///
  /// In ko, this message translates to:
  /// **'로그인에 실패했어요.'**
  String get loginFailedDefault;

  /// No description provided for @noAccountSignupPrompt.
  ///
  /// In ko, this message translates to:
  /// **'아직 계정이 없으신가요? 회원가입'**
  String get noAccountSignupPrompt;

  /// No description provided for @signupTitle.
  ///
  /// In ko, this message translates to:
  /// **'회원가입'**
  String get signupTitle;

  /// No description provided for @nicknameLabel.
  ///
  /// In ko, this message translates to:
  /// **'닉네임'**
  String get nicknameLabel;

  /// No description provided for @countryLabel.
  ///
  /// In ko, this message translates to:
  /// **'국가'**
  String get countryLabel;

  /// No description provided for @passwordHelper.
  ///
  /// In ko, this message translates to:
  /// **'8자 이상, 대소문자와 숫자를 포함해주세요.'**
  String get passwordHelper;

  /// No description provided for @countryRequiredError.
  ///
  /// In ko, this message translates to:
  /// **'국가를 선택해주세요.'**
  String get countryRequiredError;

  /// No description provided for @signupFailedDefault.
  ///
  /// In ko, this message translates to:
  /// **'회원가입에 실패했어요.'**
  String get signupFailedDefault;

  /// No description provided for @signupButton.
  ///
  /// In ko, this message translates to:
  /// **'가입하기'**
  String get signupButton;

  /// No description provided for @retryButton.
  ///
  /// In ko, this message translates to:
  /// **'다시 시도'**
  String get retryButton;

  /// No description provided for @productNotFound.
  ///
  /// In ko, this message translates to:
  /// **'상품을 찾을 수 없어요.'**
  String get productNotFound;

  /// No description provided for @homeBannerTitle.
  ///
  /// In ko, this message translates to:
  /// **'한국에 오셨다면, 이건 꼭 담아가세요'**
  String get homeBannerTitle;

  /// No description provided for @homeBannerSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'여행자들이 인정한 간식과 기념품'**
  String get homeBannerSubtitle;

  /// No description provided for @downloadAppTitle.
  ///
  /// In ko, this message translates to:
  /// **'안드로이드 앱으로 더 편하게'**
  String get downloadAppTitle;

  /// No description provided for @downloadAppSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'APK 파일을 내려받아 설치하세요'**
  String get downloadAppSubtitle;

  /// No description provided for @downloadAppButton.
  ///
  /// In ko, this message translates to:
  /// **'다운로드'**
  String get downloadAppButton;

  /// No description provided for @categoryAll.
  ///
  /// In ko, this message translates to:
  /// **'전체'**
  String get categoryAll;

  /// No description provided for @categorySnack.
  ///
  /// In ko, this message translates to:
  /// **'스낵'**
  String get categorySnack;

  /// No description provided for @categoryCosmetic.
  ///
  /// In ko, this message translates to:
  /// **'화장품'**
  String get categoryCosmetic;

  /// No description provided for @categoryLiving.
  ///
  /// In ko, this message translates to:
  /// **'생활용품'**
  String get categoryLiving;

  /// No description provided for @likesEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 좋아요한 아이템이 없어요'**
  String get likesEmpty;

  /// No description provided for @guestName.
  ///
  /// In ko, this message translates to:
  /// **'게스트 여행자'**
  String get guestName;

  /// No description provided for @guestSubtitle.
  ///
  /// In ko, this message translates to:
  /// **'둘러본 아이템을 담다에서 정리해보세요'**
  String get guestSubtitle;

  /// No description provided for @statLikes.
  ///
  /// In ko, this message translates to:
  /// **'좋아요'**
  String get statLikes;

  /// No description provided for @statBrowsed.
  ///
  /// In ko, this message translates to:
  /// **'둘러본 아이템'**
  String get statBrowsed;

  /// No description provided for @menuLanguage.
  ///
  /// In ko, this message translates to:
  /// **'언어 설정'**
  String get menuLanguage;

  /// No description provided for @menuOrders.
  ///
  /// In ko, this message translates to:
  /// **'주문 내역'**
  String get menuOrders;

  /// No description provided for @menuSupport.
  ///
  /// In ko, this message translates to:
  /// **'고객센터'**
  String get menuSupport;

  /// No description provided for @menuAbout.
  ///
  /// In ko, this message translates to:
  /// **'앱 정보'**
  String get menuAbout;

  /// No description provided for @menuLogout.
  ///
  /// In ko, this message translates to:
  /// **'로그아웃'**
  String get menuLogout;

  /// No description provided for @languagePickerTitle.
  ///
  /// In ko, this message translates to:
  /// **'언어 선택'**
  String get languagePickerTitle;

  /// No description provided for @reviewCountLabel.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 {count}'**
  String reviewCountLabel(int count);

  /// No description provided for @reviewsEmpty.
  ///
  /// In ko, this message translates to:
  /// **'아직 리뷰가 없어요. 첫 리뷰를 남겨보세요!'**
  String get reviewsEmpty;

  /// No description provided for @deleteReviewTitle.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 삭제'**
  String get deleteReviewTitle;

  /// No description provided for @deleteReviewContent.
  ///
  /// In ko, this message translates to:
  /// **'정말 삭제하시겠어요? 되돌릴 수 없어요.'**
  String get deleteReviewContent;

  /// No description provided for @cancel.
  ///
  /// In ko, this message translates to:
  /// **'취소'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In ko, this message translates to:
  /// **'삭제'**
  String get delete;

  /// No description provided for @reviewValidationError.
  ///
  /// In ko, this message translates to:
  /// **'별점과 리뷰 내용을 모두 입력해주세요.'**
  String get reviewValidationError;

  /// No description provided for @reviewFormTitleNew.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 작성하기'**
  String get reviewFormTitleNew;

  /// No description provided for @reviewFormTitleEdit.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 수정하기'**
  String get reviewFormTitleEdit;

  /// No description provided for @reviewHint.
  ///
  /// In ko, this message translates to:
  /// **'이 상품은 어떠셨나요?'**
  String get reviewHint;

  /// No description provided for @attachPhoto.
  ///
  /// In ko, this message translates to:
  /// **'사진 첨부 (선택)'**
  String get attachPhoto;

  /// No description provided for @submitReview.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 등록'**
  String get submitReview;

  /// No description provided for @askAiTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI에게 물어보기'**
  String get askAiTitle;

  /// No description provided for @askAiHint.
  ///
  /// In ko, this message translates to:
  /// **'이 상품에 대해 궁금한 걸 물어보세요'**
  String get askAiHint;

  /// No description provided for @askAiButton.
  ///
  /// In ko, this message translates to:
  /// **'물어보기'**
  String get askAiButton;

  /// No description provided for @askAiFinderTitle.
  ///
  /// In ko, this message translates to:
  /// **'AI로 찾기'**
  String get askAiFinderTitle;

  /// No description provided for @askAiFinderHint.
  ///
  /// In ko, this message translates to:
  /// **'필요한 걸 설명하면 상품을 찾아드려요'**
  String get askAiFinderHint;

  /// No description provided for @updateReview.
  ///
  /// In ko, this message translates to:
  /// **'리뷰 수정'**
  String get updateReview;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
