// Manual smoke test hitting the real Otodom site — run with:
//   dart run tool/otodom_smoke_test.dart
// Not part of `flutter test` on purpose: it depends on live network access.
// ignore_for_file: avoid_print
import 'package:househunter/models/search_criteria.dart';
import 'package:househunter/models/voivodeship.dart';
import 'package:househunter/portals/otodom_adapter.dart';

Future<void> main() async {
  final adapter = OtodomAdapter();
  final results = await adapter.search(
    const SearchCriteria(
      minPrice: 300000,
      maxPrice: 600000,
      minAreaM2: 40,
      voivodeship: Voivodeship.mazowieckie,
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
  final regionOk = results.every((r) => r.region == 'mazowieckie');
  print('price in range: $priceOk, rooms == 3: $roomsOk, region == mazowieckie: $regionOk');
  if (!priceOk || !roomsOk || !regionOk || results.isEmpty) {
    throw Exception('Smoke test assertions failed');
  }
}
