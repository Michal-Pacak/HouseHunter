// Manual smoke test hitting the real OLX API — run with:
//   dart run tool/olx_smoke_test.dart
// Not part of `flutter test` on purpose: it depends on live network access.
// ignore_for_file: avoid_print
import 'package:househunter/models/search_criteria.dart';
import 'package:househunter/models/voivodeship.dart';
import 'package:househunter/portals/olx_adapter.dart';

Future<void> main() async {
  final adapter = OlxAdapter();
  final results = await adapter.search(
    const SearchCriteria(
      minPrice: 300000,
      maxPrice: 600000,
      minAreaM2: 40,
      voivodeship: Voivodeship.wielkopolskie,
      rooms: {RoomCount.three},
    ),
    limit: 5,
  );

  print('Got ${results.length} results:');
  for (final r in results) {
    print(' - ${r.title} | ${r.price} zł | ${r.areaM2} m² | ${r.rooms} pok. | ${r.city}/${r.region} | ${r.url}');
  }

  final priceOk = results.every((r) => r.price == null || (r.price! >= 300000 && r.price! <= 600000));
  final roomsOk = results.every((r) => r.rooms == null || r.rooms == 3);
  final regionOk = results.every((r) => r.region == 'Wielkopolskie');
  print('price in range: $priceOk, rooms == 3: $roomsOk, region == Wielkopolskie: $regionOk');
  if (!priceOk || !roomsOk || !regionOk || results.isEmpty) {
    throw Exception('Smoke test assertions failed');
  }

  print('\n--- free-text district search (locationQuery: "mokotow") ---');
  final districtResults = await adapter.search(
    const SearchCriteria(locationQuery: 'mokotow'),
    limit: 5,
  );
  print('Got ${districtResults.length} results:');
  for (final r in districtResults) {
    print(' - ${r.title} | ${r.city} / ${r.district} | ${r.url}');
  }
  final districtOk = districtResults.every((r) => r.district == 'Mokotów');
  print('all in Mokotów: $districtOk');
  if (!districtOk || districtResults.isEmpty) {
    throw Exception('District smoke test assertions failed');
  }
}
