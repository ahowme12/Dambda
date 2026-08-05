class Review {
  final String userId;
  final String productId;
  final int rating;
  final String text;
  final String? photoUrl;
  final String authorNickname;
  final String createdAt;

  const Review({
    required this.userId,
    required this.productId,
    required this.rating,
    required this.text,
    required this.photoUrl,
    required this.authorNickname,
    required this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      userId: json['userId'] as String,
      productId: json['productId'] as String,
      rating: (json['rating'] as num).toInt(),
      text: json['text'] as String,
      photoUrl: json['photoUrl'] as String?,
      authorNickname: json['authorNickname'] as String,
      createdAt: json['createdAt'] as String,
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
