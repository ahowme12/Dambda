// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get navHome => '홈';

  @override
  String get navCategory => '카테고리';

  @override
  String get navLikes => '좋아요';

  @override
  String get navMy => '마이';

  @override
  String get emailLabel => '아이디 (이메일)';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get loginButton => '로그인';

  @override
  String get loginFailedDefault => '로그인에 실패했어요.';

  @override
  String get noAccountSignupPrompt => '아직 계정이 없으신가요? 회원가입';

  @override
  String get signupTitle => '회원가입';

  @override
  String get nicknameLabel => '닉네임';

  @override
  String get countryLabel => '국가';

  @override
  String get passwordHelper => '8자 이상, 대소문자와 숫자를 포함해주세요.';

  @override
  String get countryRequiredError => '국가를 선택해주세요.';

  @override
  String get signupFailedDefault => '회원가입에 실패했어요.';

  @override
  String get signupButton => '가입하기';

  @override
  String get retryButton => '다시 시도';

  @override
  String get productNotFound => '상품을 찾을 수 없어요.';

  @override
  String get homeBannerTitle => '한국에 오셨다면, 이건 꼭 담아가세요';

  @override
  String get homeBannerSubtitle => '여행자들이 인정한 간식과 기념품';

  @override
  String get downloadAppTitle => '안드로이드 앱으로 더 편하게';

  @override
  String get downloadAppSubtitle => 'APK 파일을 내려받아 설치하세요';

  @override
  String get downloadAppButton => '다운로드';

  @override
  String get categoryAll => '전체';

  @override
  String get categorySnack => '스낵';

  @override
  String get categoryCosmetic => '화장품';

  @override
  String get categoryLiving => '생활용품';

  @override
  String get likesEmpty => '아직 좋아요한 아이템이 없어요';

  @override
  String get guestName => '게스트 여행자';

  @override
  String get guestSubtitle => '둘러본 아이템을 담다에서 정리해보세요';

  @override
  String get statLikes => '좋아요';

  @override
  String get statBrowsed => '둘러본 아이템';

  @override
  String get menuLanguage => '언어 설정';

  @override
  String get menuOrders => '주문 내역';

  @override
  String get menuSupport => '고객센터';

  @override
  String get menuAbout => '앱 정보';

  @override
  String get menuLogout => '로그아웃';

  @override
  String get languagePickerTitle => '언어 선택';

  @override
  String reviewCountLabel(int count) {
    return '리뷰 $count';
  }

  @override
  String get reviewsEmpty => '아직 리뷰가 없어요. 첫 리뷰를 남겨보세요!';

  @override
  String get deleteReviewTitle => '리뷰 삭제';

  @override
  String get deleteReviewContent => '정말 삭제하시겠어요? 되돌릴 수 없어요.';

  @override
  String get cancel => '취소';

  @override
  String get delete => '삭제';

  @override
  String get reviewValidationError => '별점과 리뷰 내용을 모두 입력해주세요.';

  @override
  String get reviewFormTitleNew => '리뷰 작성하기';

  @override
  String get reviewFormTitleEdit => '리뷰 수정하기';

  @override
  String get reviewHint => '이 상품은 어떠셨나요?';

  @override
  String get attachPhoto => '사진 첨부 (선택)';

  @override
  String get submitReview => '리뷰 등록';

  @override
  String get askAiTitle => 'AI에게 물어보기';

  @override
  String get askAiHint => '이 상품에 대해 궁금한 걸 물어보세요';

  @override
  String get askAiButton => '물어보기';

  @override
  String get askAiFinderTitle => 'AI로 찾기';

  @override
  String get askAiFinderHint => '필요한 걸 설명하면 상품을 찾아드려요';

  @override
  String get updateReview => '리뷰 수정';
}
