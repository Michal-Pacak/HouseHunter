import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/property_listing.dart';
import '../models/search_criteria.dart';
import '../models/voivodeship.dart';
import '../util/polish_text.dart';
import 'portal_adapter.dart';

/// Otodom is a Next.js app that embeds its search results as JSON directly
/// in the server-rendered HTML (`<script id="__NEXT_DATA__">`), so there's
/// no separate JSON API to call — this fetches the results page itself and
/// pulls `props.pageProps.data.searchAds.items` out of it. Filters are plain
/// URL query params confirmed by requesting them and reading back the
/// echoed `filteringQueryParams` in that same JSON.
///
/// Location is a path, not a query param: `voivodeship/city` filters to a
/// city, and a district sits at `voivodeship/city/city/city/district` for
/// cities with powiat rights (the city segment really is repeated three
/// times — confirmed empirically for Warszawa and Kraków).
/// There's no public lookup for arbitrary place names, so a district is
/// only found by guessing that path directly; if the guess doesn't resolve
/// (e.g. a neighbourhood nested a level deeper, like "Stara Miłosna" under
/// the "Wesoła" district) this falls back to the city level instead of
/// failing outright.
class OtodomAdapter implements PortalAdapter {
  static const _searchRoot = 'https://www.otodom.pl/pl/wyniki/sprzedaz';

  @override
  String get portalName => 'Otodom';

  @override
  Future<List<PropertyListing>> search(SearchCriteria criteria, {int limit = 40}) async {
    final baseUrl = '$_searchRoot/${criteria.propertyType == PropertyType.house ? 'dom' : 'mieszkanie'}';
    final baseQuery = <String, String>{'limit': '$limit'};
    if (criteria.minPrice != null) baseQuery['priceMin'] = criteria.minPrice!.toStringAsFixed(0);
    if (criteria.maxPrice != null) baseQuery['priceMax'] = criteria.maxPrice!.toStringAsFixed(0);
    if (criteria.minAreaM2 != null) baseQuery['areaMin'] = criteria.minAreaM2!.toStringAsFixed(0);
    if (criteria.maxAreaM2 != null) baseQuery['areaMax'] = criteria.maxAreaM2!.toStringAsFixed(0);
    if (criteria.market != null) {
      baseQuery['market'] = criteria.market == Market.primary ? 'PRIMARY' : 'SECONDARY';
    }
    final roomValues = criteria.rooms.expand(_roomValues).toSet().toList();
    if (roomValues.isNotEmpty) {
      baseQuery['roomsNumber'] = '[${roomValues.join(',')}]';
    }

    final voivodeshipSlug = criteria.voivodeship?.otodomSlug;
    final citySlug = (criteria.cityName?.isNotEmpty ?? false) ? slugify(criteria.cityName!) : null;
    final districtSlug =
        (criteria.locationQuery?.trim().isNotEmpty ?? false) ? slugify(criteria.locationQuery!.trim()) : null;

    if (voivodeshipSlug != null && citySlug != null && districtSlug != null) {
      final guess = '$voivodeshipSlug/$citySlug/$citySlug/$citySlug/$districtSlug';
      final guessResult = await _fetchAndParse(baseUrl, guess, baseQuery, limit, expectLocationMatch: true);
      if (guessResult != null) return guessResult;
    }

    if (voivodeshipSlug != null && citySlug != null) {
      final cityResult = await _fetchAndParse(
          baseUrl, '$voivodeshipSlug/$citySlug', baseQuery, limit, expectLocationMatch: true);
      if (cityResult != null) return cityResult;
    }

    if (voivodeshipSlug != null) {
      final voivodeshipResult =
          await _fetchAndParse(baseUrl, voivodeshipSlug, baseQuery, limit, expectLocationMatch: true);
      if (voivodeshipResult != null) return voivodeshipResult;
    }

    return await _fetchAndParse(baseUrl, 'cala-polska', baseQuery, limit, expectLocationMatch: false) ?? [];
  }

  /// Fetches one location-path variant. Returns null if the path didn't
  /// resolve to a real place (Otodom serves a small fallback page for an
  /// unknown path) so the caller can retry with a broader location.
  Future<List<PropertyListing>?> _fetchAndParse(
    String baseUrl,
    String locationSegment,
    Map<String, String> baseQuery,
    int limit, {
    required bool expectLocationMatch,
  }) async {
    final uri = Uri.parse('$baseUrl/$locationSegment').replace(queryParameters: baseQuery);
    final response = await http.get(
      uri,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    );
    if (response.statusCode != 200) {
      // A guessed location path can 404 outright (Otodom isn't consistent
      // about serving its small fallback page with a 200 instead) — that
      // just means this guess didn't resolve, not a real request failure,
      // unless this was already the final, unconditional fallback.
      if (expectLocationMatch) return null;
      throw Exception('Otodom request failed: HTTP ${response.statusCode}');
    }

    final match = RegExp(
      r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(response.body);
    if (match == null) {
      if (expectLocationMatch) return null;
      throw Exception('Otodom response did not contain __NEXT_DATA__');
    }

    final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final pageProps = data['props']?['pageProps'] as Map<String, dynamic>?;
    final filteringQueryParams = pageProps?['filteringQueryParams'] as Map<String, dynamic>?;
    final locations = filteringQueryParams?['locations'] as List<dynamic>?;
    if (expectLocationMatch && (locations == null || locations.isEmpty)) {
      return null;
    }

    final items = pageProps?['data']?['searchAds']?['items'] as List<dynamic>? ?? [];
    // Otodom ignores the `limit` query param (always returns a full page,
    // usually 36 items), so the limit is enforced client-side here.
    return items.take(limit).map((raw) => _toListing(raw as Map<String, dynamic>)).toList();
  }

  /// Otodom's `roomsNumber` enum only goes up to `FIVE` (no bare "N+"
  /// option), so RoomCount.four ("4+" in the UI) is approximated as
  /// FOUR-or-FIVE.
  List<String> _roomValues(RoomCount r) => switch (r) {
        RoomCount.one => const ['ONE'],
        RoomCount.two => const ['TWO'],
        RoomCount.three => const ['THREE'],
        RoomCount.four => const ['FOUR', 'FIVE'],
      };

  PropertyListing _toListing(Map<String, dynamic> raw) {
    final address = raw['location']?['address'] as Map<String, dynamic>? ?? {};
    final city = address['city']?['name'] as String? ?? '';
    final province = address['province']?['name'] as String? ?? '';
    final reverseGeoLocations =
        raw['location']?['reverseGeocoding']?['locations'] as List<dynamic>? ?? [];
    final districtEntry = reverseGeoLocations.cast<Map<String, dynamic>>().where(
          (l) => l['locationLevel'] == 'district',
        );
    final district = districtEntry.isEmpty ? null : districtEntry.first['name'] as String?;
    final totalPrice = raw['totalPrice'] as Map<String, dynamic>?;
    final slug = raw['slug'] as String? ?? '';
    final images = (raw['images'] as List<dynamic>? ?? [])
        .map((img) => (img as Map<String, dynamic>)['large'] as String?)
        .whereType<String>()
        .toList();

    return PropertyListing(
      portal: portalName,
      externalId: '${raw['id']}',
      url: 'https://www.otodom.pl/pl/oferta/$slug',
      title: raw['title'] as String? ?? '',
      price: (totalPrice?['value'] as num?)?.toDouble(),
      areaM2: (raw['areaInSquareMeters'] as num?)?.toDouble(),
      rooms: _parseRoomsNumber(raw['roomsNumber'] as String?),
      city: city,
      district: district,
      region: province,
      market: raw['market'] as String?,
      floor: raw['floorNumber'] as String?,
      buildType: raw['buildingType'] as String?,
      photoUrls: images,
      createdAt: DateTime.tryParse(raw['dateCreated'] as String? ?? ''),
    );
  }

  int? _parseRoomsNumber(String? value) => switch (value) {
        'ONE' => 1,
        'TWO' => 2,
        'THREE' => 3,
        'FOUR' => 4,
        'FIVE' => 5,
        _ => null,
      };
}
