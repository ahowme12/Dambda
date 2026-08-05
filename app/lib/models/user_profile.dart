class UserProfile {
  final String userId;
  final String email;
  final String nickname;
  final String country;

  const UserProfile({
    required this.userId,
    required this.email,
    required this.nickname,
    required this.country,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String,
      email: json['email'] as String,
      nickname: json['nickname'] as String,
      country: json['country'] as String,
    );
  }
}
