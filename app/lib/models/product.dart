class Product {
  final String id;
  final String name;
  final int price;
  final String store;
  final String category;
  final String? reason;
  final String? discountInfo;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.store,
    required this.category,
    this.reason,
    this.discountInfo,
    this.imageUrl,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['itemId'] as String,
    name: json['name'] as String,
    price: json['price'] as int,
    store: json['store'] as String,
    category: json['category'] as String,
    reason: json['reason'] as String?,
    discountInfo: json['discountInfo'] as String?,
    imageUrl: json['imageUrl'] as String?,
  );

  String get priceLabel {
    final text = price.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
    return '$text원';
  }
}
