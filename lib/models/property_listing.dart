/// A property listing normalized from any portal into one common shape.
class PropertyListing {
  final String portal;
  final String externalId;
  final String url;
  final String title;
  final double? price;
  final double? areaM2;
  final int? rooms;
  final String city;
  final String? district;
  final String region;
  final String? market;
  final String? floor;
  final String? buildType;
  final List<String> photoUrls;
  final DateTime? createdAt;

  const PropertyListing({
    required this.portal,
    required this.externalId,
    required this.url,
    required this.title,
    required this.city,
    required this.region,
    this.price,
    this.areaM2,
    this.rooms,
    this.district,
    this.market,
    this.floor,
    this.buildType,
    this.photoUrls = const [],
    this.createdAt,
  });

  double? get pricePerM2 =>
      (price != null && areaM2 != null && areaM2! > 0) ? price! / areaM2! : null;
}
