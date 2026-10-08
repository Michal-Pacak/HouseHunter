import 'voivodeship.dart';

enum RoomCount { one, two, three, four }

enum Market { primary, secondary }

enum PropertyType { flat, house }

/// Portal-agnostic search criteria. Each portal adapter maps this onto its
/// own query parameters (see PortalAdapter implementations).
class SearchCriteria {
  final double? minPrice;
  final double? maxPrice;
  final double? minAreaM2;
  final double? maxAreaM2;
  final Set<RoomCount> rooms;
  final Voivodeship? voivodeship;
  final Market? market;
  final PropertyType propertyType;

  /// A structured city name, e.g. "Warszawa" — resolved once (via
  /// `CityResolver`, against OLX's data) from the "City, District" text the
  /// user typed, and shared across every portal adapter. When set, adapters
  /// that support a real city-level filter (OLX `city_id`, Otodom's
  /// location path) should use it instead of falling back to free text.
  final String? cityName;

  /// OLX's numeric id for [cityName], resolved alongside it. Null if
  /// [cityName] is null or couldn't be resolved to a known OLX city.
  final int? olxCityId;

  /// Free-text filter — the district/neighbourhood part when [cityName] is
  /// set (e.g. "Wesoła" after the user typed "Warszawa, Wesoła"), or the
  /// whole typed text otherwise (e.g. just "Mokotów"). Portals that support
  /// free-text search (OLX: `query` param) narrow results to this text;
  /// portals without it may ignore it.
  final String? locationQuery;

  const SearchCriteria({
    this.minPrice,
    this.maxPrice,
    this.minAreaM2,
    this.maxAreaM2,
    this.rooms = const {},
    this.voivodeship,
    this.market,
    this.propertyType = PropertyType.flat,
    this.cityName,
    this.olxCityId,
    this.locationQuery,
  });
}
