// Manual smoke test hitting the real Nieruchomości-online site — run with:
//   dart run tool/nol_smoke_test.dart
// Not part of `flutter test` on purpose: it depends on live network access.
// ignore_for_file: avoid_print
import 'package:househunter/models/search_criteria.dart';
import 'package:househunter/models/voivodeship.dart';
import 'package:househunter/portals/nol_adapter.dart';

Future<void> main() async {
  final adapter = NolAdapter();

  final unfiltered = await adapter.search(const SearchCriteria(), limit: 100);
  print('Unfiltered fetch: ${unfiltered.length} listings parsed from the page.');
  if (unfiltered.isEmpty) {
    throw Exception('Parsed zero listings — the page structure likely changed.');
  }
  for (final r in unfiltered.take(3)) {
    print(' - ${r.title} | ${r.price} zł | ${r.areaM2} m² | ${r.rooms} pok. | ${r.market} | '
        '${r.city}/${r.region} | ${r.url}');
  }

  print('\n--- client-side filtered: 300k-600k, 3 rooms ---');
  final filtered = await adapter.search(
    const SearchCriteria(minPrice: 300000, maxPrice: 600000, rooms: {RoomCount.three}),
  );
  print('Got ${filtered.length} results:');
  for (final r in filtered) {
    print(' - ${r.title} | ${r.price} zł | ${r.rooms} pok. | ${r.city}');
  }
  final priceOk = filtered.every((r) => r.price != null && r.price! >= 300000 && r.price! <= 600000);
  final roomsOk = filtered.every((r) => r.rooms == 3);
  print('price in range: $priceOk, rooms == 3: $roomsOk');
  if (!priceOk || !roomsOk) {
    throw Exception('Filter smoke test assertions failed');
  }

  print('\n--- regression: dom, do 1 500 000 zł, Mazowieckie, Warszawa/Wesoła ---');
  final wesola = await adapter.search(
    const SearchCriteria(
      propertyType: PropertyType.house,
      maxPrice: 1500000,
      voivodeship: Voivodeship.mazowieckie,
      cityName: 'Warszawa',
      locationQuery: 'Wesoła',
    ),
    limit: 40,
  );
  print('Got ${wesola.length} results (previously 0 — city subdomain + pagination fixes this):');
  for (final r in wesola) {
    print(' - ${r.title} | ${r.price} zł | ${r.city} | ${r.url}');
  }
  if (wesola.isEmpty) {
    throw Exception('Regression: Warszawa/Wesoła house search returned zero results again');
  }
}
