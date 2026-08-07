class Review {
  final String userId;
  final String productId;
  final int rating;
  final String text;
  final String? photoUrl;
  final String authorNickname;
  final String createdAt;
  // 비동기 검열 파이프라인 도입 이전에 만들어진 리뷰는 이 값이 없음(=이미 통과된 것으로 취급)
  final String? moderationStatus;

  const Review({
    required this.userId,
    required this.productId,
    required this.rating,
    required this.text,
    required this.photoUrl,
    required this.authorNickname,
    required this.createdAt,
    this.moderationStatus,
  });

  bool get isPending => moderationStatus == 'PENDING';
  // worker Lambda가 검열에 걸려 비공개 처리한 상태 - 백엔드가 작성자 본인에게는 자기 리뷰를
  // 그대로 보여주므로(isVisible=false여도), 클라이언트에서 "검토 중"과 구분해서 표시해야
  // 차단된 걸 정상 게시된 것처럼 착각하지 않음
  bool get isBlocked => moderationStatus == 'REVIEW_REQUIRED';

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      userId: json['userId'] as String,
      productId: json['productId'] as String,
      rating: (json['rating'] as num).toInt(),
      text: json['text'] as String,
      photoUrl: json['photoUrl'] as String?,
      authorNickname: json['authorNickname'] as String,
      createdAt: json['createdAt'] as String,
      moderationStatus: json['moderationStatus'] as String?,
    );
  }
}

class ReviewsResult {
  final List<Review> reviews;
  final double averageRating;
  final int reviewCount;

  const ReviewsResult({
    required this.reviews,
    required this.averageRating,
    required this.reviewCount,
  });

  factory ReviewsResult.fromJson(Map<String, dynamic> json) {
    return ReviewsResult(
      reviews: (json['reviews'] as List)
          .map((e) => Review.fromJson(e as Map<String, dynamic>))
          .toList(),
      averageRating: (json['averageRating'] as num).toDouble(),
      reviewCount: (json['reviewCount'] as num).toInt(),
    );
  }
}
