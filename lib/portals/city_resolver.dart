import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/voivodeship.dart';
import '../util/polish_text.dart';

/// A Polish city resolved to the identifiers each portal needs: OLX's
/// numeric `city_id` and the voivodeship it's in (which Otodom's location
/// URLs require as a path prefix).
class ResolvedCity {
  final String name;
  final int olxCityId;
  final Voivodeship? voivodeship;

  const ResolvedCity({required this.name, required this.olxCityId, this.voivodeship});
}

/// Resolves a free-typed city name (e.g. "Warszawa") against OLX's own
/// offers API, since OLX has no public geo-lookup endpoint: this searches
/// for the city name as free text and reads the city/region back off the
/// first matching listing. This is shared across all portal adapters so
/// city resolution only happens once per search, rather than once per
/// portal.
class CityResolver {
  static const _searchUrl = 'https://www.olx.pl/api/v1/offers/';

  Future<ResolvedCity?> resolve(String cityName) async {
    final trimmed = cityName.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'category_id': '14',
      'query': trimmed,
      'limit': '20',
    });
    final response = await http.get(
      uri,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        'Accept': 'application/json',
      },
    );
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    final target = normalizeForCompare(trimmed);

    for (final raw in data) {
      final location = (raw as Map<String, dynamic>)['location'] as Map<String, dynamic>?;
      final city = location?['city'] as Map<String, dynamic>?;
      final cityName2 = city?['name'] as String?;
      if (cityName2 == null || normalizeForCompare(cityName2) != target) continue;

      final regionName = (location?['region'] as Map<String, dynamic>?)?['name'] as String?;
      return ResolvedCity(
        name: cityName2,
        olxCityId: city!['id'] as int,
        voivodeship: _matchVoivodeship(regionName),
      );
    }
    return null;
  }

  Voivodeship? _matchVoivodeship(String? name) {
    if (name == null) return null;
    final target = normalizeForCompare(name);
    for (final v in Voivodeship.values) {
      if (normalizeForCompare(v.displayName) == target) return v;
    }
    return null;
  }
}
