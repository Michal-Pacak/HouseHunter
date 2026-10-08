// Manual smoke test for PropertyType.house across all three portals — run
// with:
//   dart run tool/house_smoke_test.dart
// Not part of `flutter test` on purpose: it depends on live network access.
// ignore_for_file: avoid_print
import 'package:househunter/models/search_criteria.dart';
import 'package:househunter/portals/nol_adapter.dart';
import 'package:househunter/portals/olx_adapter.dart';
import 'package:househunter/portals/otodom_adapter.dart';

Future<void> main() async {
  const criteria = SearchCriteria(propertyType: PropertyType.house, minPrice: 300000, maxPrice: 900000);

  final olx = await OlxAdapter().search(criteria, limit: 5);
  print('OLX (dom): ${olx.length} results');
  for (final r in olx) {
    print(' - ${r.title} | ${r.price} zł | ${r.city} | ${r.url}');
  }
  if (olx.isEmpty) throw Exception('OLX returned zero houses');

  final otodom = await OtodomAdapter().search(criteria, limit: 5);
  print('\nOtodom (dom): ${otodom.length} results');
  for (final r in otodom) {
    print(' - ${r.title} | ${r.price} zł | ${r.city} | ${r.url}');
  }
  if (otodom.isEmpty) throw Exception('Otodom returned zero houses');

  final nol = await NolAdapter().search(criteria, limit: 40);
  print('\nNOL (dom): ${nol.length} results');
  for (final r in nol.take(5)) {
    print(' - ${r.title} | ${r.price} zł | ${r.city} | ${r.url}');
  }
  if (nol.isEmpty) throw Exception('NOL returned zero houses');

  print('\nAll three portals returned houses.');
}
