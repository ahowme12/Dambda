// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navHome => 'Home';

  @override
  String get navCategory => 'Categories';

  @override
  String get navLikes => 'Likes';

  @override
  String get navMy => 'My';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get loginButton => 'Log In';

  @override
  String get loginFailedDefault => 'Login failed.';

  @override
  String get noAccountSignupPrompt => 'Don\'t have an account? Sign up';

  @override
  String get signupTitle => 'Sign Up';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get countryLabel => 'Country';

  @override
  String get passwordHelper =>
      'At least 8 characters, including upper/lowercase letters and numbers.';

  @override
  String get countryRequiredError => 'Please select a country.';

  @override
  String get signupFailedDefault => 'Signup failed.';

  @override
  String get signupButton => 'Sign Up';

  @override
  String get retryButton => 'Retry';

  @override
  String get productNotFound => 'Product not found.';

  @override
  String get homeBannerTitle => 'If you\'re visiting Korea, don\'t miss these';

  @override
  String get homeBannerSubtitle => 'Traveler-approved snacks & souvenirs';

  @override
  String get downloadAppTitle => 'Get the Android app';

  @override
  String get downloadAppSubtitle => 'Download the APK and install it';

  @override
  String get downloadAppButton => 'Download';

  @override
  String get categoryAll => 'All';

  @override
  String get categorySnack => 'Snacks';

  @override
  String get categoryCosmetic => 'Cosmetics';

  @override
  String get categoryLiving => 'Living';

  @override
  String get likesEmpty => 'No liked items yet';

  @override
  String get guestName => 'Guest Traveler';

  @override
  String get guestSubtitle => 'Keep track of items you\'ve browsed in DAMBDA';

  @override
  String get statLikes => 'Likes';

  @override
  String get statBrowsed => 'Items Browsed';

  @override
  String get menuLanguage => 'Language';

  @override
  String get menuOrders => 'Order History';

  @override
  String get menuSupport => 'Support';

  @override
  String get menuAbout => 'About';

  @override
  String get menuLogout => 'Log Out';

  @override
  String get languagePickerTitle => 'Select Language';

  @override
  String reviewCountLabel(int count) {
    return '$count Reviews';
  }

  @override
  String get reviewsEmpty => 'No reviews yet. Be the first to leave one!';

  @override
  String get deleteReviewTitle => 'Delete Review';

  @override
  String get deleteReviewContent =>
      'Are you sure you want to delete this? This can\'t be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get reviewValidationError =>
      'Please enter both a rating and review text.';

  @override
  String get reviewFormTitleNew => 'Write a Review';

  @override
  String get reviewFormTitleEdit => 'Edit Review';

  @override
  String get reviewHint => 'How was this product?';

  @override
  String get attachPhoto => 'Attach Photo (optional)';

  @override
  String get submitReview => 'Submit Review';

  @override
  String get askAiTitle => 'Ask AI';

  @override
  String get askAiHint => 'Ask anything about this product';

  @override
  String get askAiButton => 'Ask';

  @override
  String get askAiFinderTitle => 'Find with AI';

  @override
  String get askAiFinderHint => 'Describe what you need and we\'ll find it';

  @override
  String get updateReview => 'Update Review';
}
