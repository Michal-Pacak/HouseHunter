import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/property_listing.dart';
import '../models/search_criteria.dart';
import '../models/voivodeship.dart';
import '../util/polish_text.dart';
import 'portal_adapter.dart';

/// Nieruchomości-online serves plain server-rendered HTML (no embedded JSON,
/// unlike OLX/Otodom) — this parses the listing "tile" cards directly out
/// of the page(s).
///
/// price/area/rooms/market filters are NOT sent to the server: every attempt
/// to pass them as URL query params (matching the search-alert form's field
/// names, e.g. `priceFrom`) was silently ignored — the real search page
/// builds its filtered URL via client-side JavaScript that isn't visible in
/// the static HTML. So those filters are applied locally, in Dart, on top
/// of whatever this fetches.
///
/// Location, however, *does* have a real server-side filter: every city and
/// voivodeship has its own subdomain (e.g. `warszawa.nieruchomosci-online.pl`,
/// `mazowieckie.nieruchomosci-online.pl`), discovered from the location
/// links on listing tiles, and those pages paginate with `?p=N`. So when a
/// city (or at least a voivodeship) is known, this fetches several pages
/// from that scoped subdomain instead of one nationwide page — e.g.
/// searching "Warszawa, Wesoła" used to silently search ~44 *nationwide*
/// listings (almost certainly none of which were in Wesoła) and report zero
/// results even though the portal itself has real matches; now it searches
/// several hundred *Warszawa* listings instead, which actually contain them.
/// There's no working district-level URL (guesses at one just 404), so a
/// district/neighbourhood is still applied as free-text matching on top of
/// the city-scoped fetch, per an explicit user decision to keep this
/// portal's (unfiltered-by-the-server-but-locally-filterable) results in
/// their own UI tab rather than merge them into the main cross-portal
/// search.
class NolAdapter implements PortalAdapter {
  @override
  String get portalName => 'Nieruchomości-online';

  @override
  Future<List<PropertyListing>> search(SearchCriteria criteria, {int limit = 40}) async {
    final singular = criteria.propertyType == PropertyType.house ? 'dom' : 'mieszkanie';
    final plural = criteria.propertyType == PropertyType.house ? 'domy' : 'mieszkania';

    late final String basePath;
    late final int maxPages;
    late final bool locationScopedByFetch;
    if (criteria.cityName != null && criteria.cityName!.isNotEmpty) {
      basePath = 'https://${slugify(criteria.cityName!)}.nieruchomosci-online.pl/$plural,sprzedaz/';
      maxPages = 10;
      locationScopedByFetch = true;
    } else if (criteria.voivodeship != null) {
      basePath = 'https://${slugify(criteria.voivodeship!.displayName)}.nieruchomosci-online.pl/$plural,sprzedaz/';
      maxPages = 3;
      locationScopedByFetch = true;
    } else {
      basePath = 'https://www.nieruchomosci-online.pl/szukaj.html?3,$singular,sprzedaz';
      maxPages = 1;
      locationScopedByFetch = false;
    }

    final firstPageBody = await _fetchPage(basePath);
    final seenIds = <String>{};
    final all = <PropertyListing>[];
    if (firstPageBody == null) return [];

    final firstDocument = html_parser.parse(firstPageBody);
    _collectTiles(firstDocument, seenIds, all);

    // Fetch however many more pages actually exist, capped at maxPages —
    // a city's inventory is often much smaller than that cap (a search can
    // otherwise miss real matches sitting on a later page, which is what
    // originally made "Warszawa, Wesoła" wrongly report zero results).
    final lastPageNumber = _lastPageNumber(firstDocument);
    final pagesToFetch = lastPageNumber == null ? 1 : lastPageNumber.clamp(1, maxPages);
    if (pagesToFetch > 1) {
      final urls = [for (var p = 2; p <= pagesToFetch; p++) '$basePath?p=$p'];
      final restBodies = await Future.wait(urls.map(_fetchPage));
      for (final body in restBodies) {
        if (body == null) continue;
        _collectTiles(html_parser.parse(body), seenIds, all);
      }
    }

    return all.where((l) => _matches(l, criteria, locationScopedByFetch: locationScopedByFetch)).take(limit).toList();
  }

  void _collectTiles(Document document, Set<String> seenIds, List<PropertyListing> out) {
    final tiles = document.querySelectorAll('div.tile.tile-tile').where((t) => t.attributes.containsKey('data-id'));
    for (final tile in tiles) {
      final listing = _toListing(tile);
      if (seenIds.add(listing.externalId)) out.add(listing);
    }
  }

  int? _lastPageNumber(Document document) {
    final pageNumbers = document
        .querySelectorAll('.pagination a')
        .map((a) => int.tryParse(a.text.trim()))
        .whereType<int>()
        .toList();
    if (pageNumbers.isEmpty) return null;
    return pageNumbers.reduce((a, b) => a > b ? a : b);
  }

  Future<String?> _fetchPage(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      },
    );
    if (response.statusCode != 200) return null;
    return response.body;
  }

  bool _matches(PropertyListing l, SearchCriteria c, {required bool locationScopedByFetch}) {
    if (c.minPrice != null && (l.price == null || l.price! < c.minPrice!)) return false;
    if (c.maxPrice != null && (l.price == null || l.price! > c.maxPrice!)) return false;
    if (c.minAreaM2 != null && (l.areaM2 == null || l.areaM2! < c.minAreaM2!)) return false;
    if (c.maxAreaM2 != null && (l.areaM2 == null || l.areaM2! > c.maxAreaM2!)) return false;
    if (c.rooms.isNotEmpty) {
      final wantsFourPlus = c.rooms.contains(RoomCount.four);
      final matchesRooms = l.rooms != null &&
          (c.rooms.any((r) => _roomCountValue(r) == l.rooms) || (wantsFourPlus && l.rooms! >= 4));
      if (!matchesRooms) return false;
    }
    if (c.market != null) {
      final wanted = c.market == Market.primary ? 'primary' : 'secondary';
      if (l.market != wanted) return false;
    }
    // When the fetch itself was already scoped to a city/voivodeship
    // subdomain, that's a real structural guarantee — skip re-checking
    // voivodeship/city fields on each tile. Some tiles genuinely can't be
    // checked here anyway: former independent towns later annexed into a
    // bigger city (e.g. Wesoła into Warszawa) are shown with *only* that
    // former-town name as the tile's "city" link and no voivodeship link
    // at all, so a strict equality check against "Warszawa"/"Mazowieckie"
    // would wrongly reject a real, correctly-scoped result.
    if (!locationScopedByFetch) {
      if (c.voivodeship != null &&
          normalizeForCompare(l.region) != normalizeForCompare(c.voivodeship!.displayName)) {
        return false;
      }
      if (c.cityName != null && c.cityName!.isNotEmpty) {
        if (normalizeForCompare(l.city) != normalizeForCompare(c.cityName!)) return false;
      }
    }
    if (c.locationQuery != null && c.locationQuery!.trim().isNotEmpty) {
      final needle = normalizeForCompare(c.locationQuery!.trim());
      final haystack = normalizeForCompare('${l.title} ${l.city} ${l.region}');
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }

  int _roomCountValue(RoomCount r) => switch (r) {
        RoomCount.one => 1,
        RoomCount.two => 2,
        RoomCount.three => 3,
        RoomCount.four => 4,
      };

  PropertyListing _toListing(Element tile) {
    final id = tile.attributes['data-id'] ?? '';
    final marketType = tile.attributes['data-market-type'];
    final titleLink = tile.querySelector('h2.name a');
    final url = titleLink?.attributes['href'] ?? '';
    final title = titleLink?.text.trim() ?? '';

    final provinceLinks = tile.querySelectorAll('p.province a');
    final city = provinceLinks.isNotEmpty ? provinceLinks[0].text.trim().replaceAll(',', '') : '';
    final region = provinceLinks.length > 1 ? provinceLinks[1].text.trim() : '';

    final priceSpans = tile.querySelectorAll('.primary-display span');
    final price = priceSpans.isNotEmpty ? _parseNumber(priceSpans[0].text) : null;
    final area = priceSpans.length > 1 ? _parseNumber(priceSpans[1].text) : null;

    int? rooms;
    String? floor;
    for (final item in tile.querySelectorAll('.attributes__box--item')) {
      final iconClasses = item.querySelector('em')?.classes ?? {};
      final values = item.querySelectorAll('strong').map((s) => s.text.trim()).toList();
      if (iconClasses.contains('icon-data-rooms') && values.isNotEmpty) {
        rooms = int.tryParse(values.first);
      } else if (iconClasses.contains('icon-data-floor') && values.isNotEmpty) {
        floor = values.join('');
      }
    }

    return PropertyListing(
      portal: portalName,
      externalId: id,
      url: url,
      title: title,
      price: price,
      areaM2: area,
      rooms: rooms,
      city: city,
      district: null,
      region: region,
      market: marketType,
      floor: floor,
    );
  }

  double? _parseNumber(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^\d,]'), '').replaceAll(',', '.');
    return double.tryParse(cleaned);
  }
}
