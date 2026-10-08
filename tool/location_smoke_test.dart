// Manual smoke test for the "Miasto, Dzielnica" resolution flow — run with:
//   dart run tool/location_smoke_test.dart
// Not part of `flutter test` on purpose: it depends on live network access.
// ignore_for_file: avoid_print
import 'package:househunter/models/search_criteria.dart';
import 'package:househunter/portals/city_resolver.dart';
import 'package:househunter/portals/nol_adapter.dart';
import 'package:househunter/portals/olx_adapter.dart';
import 'package:househunter/portals/otodom_adapter.dart';

Future<SearchCriteria> _resolve(CityResolver resolver, String cityPart, String? districtPart) async {
  final resolved = await resolver.resolve(cityPart);
  print('Resolved "$cityPart" -> ${resolved == null ? 'NOT FOUND' : '${resolved.name} '
      '(olxCityId=${resolved.olxCityId}, voivodeship=${resolved.voivodeship})'}');
  return SearchCriteria(
    voivodeship: resolved?.voivodeship,
    cityName: resolved?.name ?? cityPart,
    olxCityId: resolved?.olxCityId,
    locationQuery: districtPart,
  );
}

Future<void> main() async {
  final resolver = CityResolver();

  print('=== "Warszawa, Wesoła" (real district, one level under the city) ===');
  final wesola = await _resolve(resolver, 'Warszawa', 'Wesoła');

  final olxResults = await OlxAdapter().search(wesola, limit: 5);
  print('OLX: ${olxResults.length} results, all in Warszawa? '
      '${olxResults.every((r) => r.city == 'Warszawa')}');
  for (final r in olxResults) {
    print(' - ${r.title} | ${r.city}/${r.district}');
  }

  final otodomResults = await OtodomAdapter().search(wesola, limit: 5);
  print('Otodom: ${otodomResults.length} results, all in Warszawa? '
      '${otodomResults.every((r) => r.city == 'Warszawa')}, '
      'all in Wesoła? ${otodomResults.every((r) => r.district == 'Wesoła')}');
  for (final r in otodomResults) {
    print(' - ${r.title} | ${r.city}/${r.district}');
  }

  final nolResults = await NolAdapter().search(wesola);
  print('NOL: ${nolResults.length} results out of the fixed unfiltered page '
      '(0 is possible — small sample size)');

  print('\n=== "Warszawa, Stara Miłosna" (nested one level deeper than a district) ===');
  final staraMilosna = await _resolve(resolver, 'Warszawa', 'Stara Miłosna');
  final otodomNested = await OtodomAdapter().search(staraMilosna, limit: 5);
  print('Otodom (expected: falls back to city-level, since the guessed path is one level too shallow): '
      '${otodomNested.length} results, all in Warszawa? '
      '${otodomNested.every((r) => r.city == 'Warszawa')}');

  if (olxResults.isEmpty || !olxResults.every((r) => r.city == 'Warszawa')) {
    throw Exception('OLX city-scoped district search failed');
  }
  if (otodomResults.isEmpty || !otodomResults.every((r) => r.district == 'Wesoła')) {
    throw Exception('Otodom district search failed');
  }
  print('\nAll checks passed.');
}
