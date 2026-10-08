import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/property_listing.dart';
import '../models/search_criteria.dart';
import '../models/voivodeship.dart';
import 'portal_adapter.dart';

/// Talks directly to OLX's own internal listings API (the same one
/// www.olx.pl's web frontend calls) — no official public API exists, so
/// this mirrors what the site itself sends. Sale category ids, found by
/// probing category_id=14..20 and reading back listing titles: 14 =
/// mieszkania (flats), 15 = mieszkania wynajem (flat rentals), 18 = domy
/// (houses), 20 = domy wynajem (house rentals).
class OlxAdapter implements PortalAdapter {
  static const _baseUrl = 'https://www.olx.pl/api/v1/offers/';
  static const _flatSaleCategoryId = 14;
  static const _houseSaleCategoryId = 18;

  @override
  String get portalName => 'OLX';

  @override
  Future<List<PropertyListing>> search(SearchCriteria criteria, {int limit = 40}) async {
    final categoryId = criteria.propertyType == PropertyType.house ? _houseSaleCategoryId : _flatSaleCategoryId;
    final query = <String, String>{
      'category_id': '$categoryId',
      'limit': '$limit',
    };

    if (criteria.minPrice != null) {
      query['filter_float_price:from'] = criteria.minPrice!.toStringAsFixed(0);
    }
    if (criteria.maxPrice != null) {
      query['filter_float_price:to'] = criteria.maxPrice!.toStringAsFixed(0);
    }
    if (criteria.minAreaM2 != null) {
      query['filter_float_m:from'] = criteria.minAreaM2!.toStringAsFixed(0);
    }
    if (criteria.maxAreaM2 != null) {
      query['filter_float_m:to'] = criteria.maxAreaM2!.toStringAsFixed(0);
    }
    if (criteria.olxCityId != null) {
      // A resolved city is strictly more precise than the voivodeship, so
      // it supersedes region_id rather than being combined with it.
      query['city_id'] = '${criteria.olxCityId}';
    } else if (criteria.voivodeship != null) {
      query['region_id'] = '${criteria.voivodeship!.olxRegionId}';
    }
    if (criteria.market != null) {
      query['filter_enum_market[0]'] = criteria.market == Market.primary ? 'primary' : 'secondary';
    }
    if (criteria.locationQuery != null && criteria.locationQuery!.trim().isNotEmpty) {
      query['query'] = criteria.locationQuery!.trim();
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: query);
    final roomKeys = criteria.rooms.map(_roomKey).toList();
    final fullUri = roomKeys.isEmpty
        ? uri
        : uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              for (var i = 0; i < roomKeys.length; i++) 'filter_enum_rooms[$i]': roomKeys[i],
            },
          );

    final response = await http.get(
      fullUri,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('OLX request failed: HTTP ${response.statusCode}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    return data.map((raw) => _toListing(raw as Map<String, dynamic>)).toList();
  }

  String _roomKey(RoomCount r) => switch (r) {
        RoomCount.one => 'one',
        RoomCount.two => 'two',
        RoomCount.three => 'three',
        RoomCount.four => 'four',
      };

  PropertyListing _toListing(Map<String, dynamic> raw) {
    final params = <String, dynamic>{
      for (final p in (raw['params'] as List<dynamic>? ?? []))
        (p as Map<String, dynamic>)['key'] as String: p['value'],
    };

    double? asDouble(dynamic v) => v == null ? null : double.tryParse(v.toString().replaceAll(',', '.'));

    final priceValue = params['price']?['value'];
    final areaKey = params['m']?['key'];
    final roomsLabel = params['rooms']?['label'] as String?;
    final location = raw['location'] as Map<String, dynamic>? ?? {};
    final photos = (raw['photos'] as List<dynamic>? ?? [])
        .map((p) => (p as Map<String, dynamic>)['link'] as String)
        .map((link) => link.replaceAll('{width}x{height}', '800x600'))
        .toList();

    return PropertyListing(
      portal: portalName,
      externalId: '${raw['id']}',
      url: raw['url'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      price: asDouble(priceValue),
      areaM2: asDouble(areaKey),
      rooms: _parseRoomsLabel(roomsLabel),
      city: (location['city'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      district: (location['district'] as Map<String, dynamic>?)?['name'] as String?,
      region: (location['region'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      market: params['market']?['label'] as String?,
      floor: params['floor_select']?['label'] as String?,
      buildType: params['builttype']?['label'] as String?,
      photoUrls: photos,
      createdAt: DateTime.tryParse(raw['created_time'] as String? ?? ''),
    );
  }

  int? _parseRoomsLabel(String? label) {
    if (label == null) return null;
    if (label.startsWith('1')) return 1;
    if (label.startsWith('2')) return 2;
    if (label.startsWith('3')) return 3;
    if (label.startsWith('4')) return 4;
    return null;
  }
}
