class ProductTranslation {
  final String? name;
  final String? reason;
  final String? store;
  final String? discountInfo;

  const ProductTranslation({this.name, this.reason, this.store, this.discountInfo});

  factory ProductTranslation.fromJson(Map<String, dynamic> json) => ProductTranslation(
    name: json['name'] as String?,
    reason: json['reason'] as String?,
    store: json['store'] as String?,
    discountInfo: json['discountInfo'] as String?,
  );
}

class Product {
  final String id;
  final String name;
  final int price;
  final String store;
  final String category;
  final String? reason;
  final String? discountInfo;
  final String? imageUrl;
  final Map<String, ProductTranslation> translations;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.store,
    required this.category,
    this.reason,
    this.discountInfo,
    this.imageUrl,
    this.translations = const {},
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
    translations: (json['translations'] as Map<String, dynamic>?)?.map(
          (lang, value) => MapEntry(lang, ProductTranslation.fromJson(value as Map<String, dynamic>)),
        ) ??
        const {},
  );

  String get priceLabel {
    final text = price.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
    return '₩$text';
  }

  // 해당 언어 번역이 없으면(한국어이거나 아직 번역이 없는 경우) 원문으로 자동 폴백
  String nameFor(String lang) => translations[lang]?.name ?? name;
  String? reasonFor(String lang) => translations[lang]?.reason ?? reason;
  String storeFor(String lang) => translations[lang]?.store ?? store;
  String? discountInfoFor(String lang) => translations[lang]?.discountInfo ?? discountInfo;
}
