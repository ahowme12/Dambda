// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get navHome => '首页';

  @override
  String get navCategory => '分类';

  @override
  String get navLikes => '收藏';

  @override
  String get navMy => '我的';

  @override
  String get emailLabel => '账号（邮箱）';

  @override
  String get passwordLabel => '密码';

  @override
  String get loginButton => '登录';

  @override
  String get loginFailedDefault => '登录失败了。';

  @override
  String get noAccountSignupPrompt => '还没有账号？注册';

  @override
  String get signupTitle => '注册';

  @override
  String get nicknameLabel => '昵称';

  @override
  String get countryLabel => '国家';

  @override
  String get passwordHelper => '请输入8位以上，包含大小写字母和数字。';

  @override
  String get countryRequiredError => '请选择国家。';

  @override
  String get signupFailedDefault => '注册失败了。';

  @override
  String get signupButton => '注册';

  @override
  String get retryButton => '重试';

  @override
  String get productNotFound => '找不到该商品。';

  @override
  String get homeBannerTitle => '来韩国的话，一定要带上这些';

  @override
  String get homeBannerSubtitle => '旅行者认可的零食和纪念品';

  @override
  String get downloadAppTitle => '获取安卓应用';

  @override
  String get downloadAppSubtitle => '下载APK文件并安装';

  @override
  String get downloadAppButton => '下载';

  @override
  String get categoryAll => '全部';

  @override
  String get categorySnack => '零食';

  @override
  String get categoryCosmetic => '化妆品';

  @override
  String get categoryLiving => '生活用品';

  @override
  String get likesEmpty => '还没有收藏的商品';

  @override
  String get guestName => '访客旅行者';

  @override
  String get guestSubtitle => '在DAMBDA整理您浏览过的商品';

  @override
  String get statLikes => '收藏';

  @override
  String get statBrowsed => '浏览过的商品';

  @override
  String get menuLanguage => '语言设置';

  @override
  String get menuOrders => '订单记录';

  @override
  String get menuSupport => '客服中心';

  @override
  String get menuAbout => '应用信息';

  @override
  String get menuLogout => '退出登录';

  @override
  String get languagePickerTitle => '选择语言';

  @override
  String reviewCountLabel(int count) {
    return '$count条评价';
  }

  @override
  String get reviewsEmpty => '还没有评价，写下第一条评价吧！';

  @override
  String get deleteReviewTitle => '删除评价';

  @override
  String get deleteReviewContent => '确定要删除吗？无法恢复。';

  @override
  String get cancel => '取消';

  @override
  String get delete => '删除';

  @override
  String get reviewValidationError => '请输入星级评分和评价内容。';

  @override
  String get reviewFormTitleNew => '写评价';

  @override
  String get reviewFormTitleEdit => '编辑评价';

  @override
  String get reviewHint => '这件商品怎么样？';

  @override
  String get attachPhoto => '添加照片（可选）';

  @override
  String get submitReview => '提交评价';

  @override
  String get askAiTitle => '问问 AI';

  @override
  String get askAiHint => '问问关于这个商品的任何问题';

  @override
  String get askAiButton => '提问';

  @override
  String get askAiFinderTitle => '用 AI 查找';

  @override
  String get askAiFinderHint => '描述你需要的商品，我们帮你找';

  @override
  String get updateReview => '修改评价';
}
