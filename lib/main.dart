import 'package:flutter/material.dart';

import 'models/property_listing.dart';
import 'models/search_criteria.dart';
import 'models/voivodeship.dart';
import 'portals/city_resolver.dart';
import 'portals/nol_adapter.dart';
import 'portals/olx_adapter.dart';
import 'portals/otodom_adapter.dart';
import 'portals/portal_adapter.dart';

void main() {
  runApp(const HouseHunterApp());
}

class HouseHunterApp extends StatelessWidget {
  const HouseHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HouseHunter',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const SearchScreen(),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // OLX and Otodom both apply criteria server-side, so their results are
  // merged into one combined tab. Nieruchomości-online can't be filtered
  // server-side (see nol_adapter.dart) — it always fetches the same
  // unfiltered page and applies criteria locally, so it gets its own tab
  // rather than being mixed into the "real" cross-portal search results.
  final List<PortalAdapter> _portals = [OlxAdapter(), OtodomAdapter()];
  final _nol = NolAdapter();
  final _cityResolver = CityResolver();
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  final _minAreaCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  Voivodeship? _selectedVoivodeship;
  PropertyType _selectedType = PropertyType.flat;
  final Set<RoomCount> _selectedRooms = {};

  bool _loading = false;
  String? _error;
  List<PropertyListing> _results = [];
  List<PropertyListing> _nolResults = [];

  Future<Object> _safeSearch(PortalAdapter portal, SearchCriteria criteria) async {
    try {
      return await portal.search(criteria);
    } catch (e) {
      return _PortalError(portal.portalName, e);
    }
  }

  Future<void> _runSearch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // "Miasto, Dzielnica" (e.g. "Warszawa, Wesoła") is resolved to a
    // structured city once here and shared by every adapter, rather than
    // treating the whole string as one free-text term — a plain keyword
    // search for just "Wesoła" also matches other places with a district
    // of the same name (e.g. Mysłowice has one too).
    final rawLocation = _locationCtrl.text.trim();
    String? cityPart;
    String? districtPart;
    if (rawLocation.contains(',')) {
      final commaIndex = rawLocation.indexOf(',');
      cityPart = rawLocation.substring(0, commaIndex).trim();
      districtPart = rawLocation.substring(commaIndex + 1).trim();
    }

    ResolvedCity? resolvedCity;
    if (cityPart != null && cityPart.isNotEmpty) {
      try {
        resolvedCity = await _cityResolver.resolve(cityPart);
      } catch (_) {
        resolvedCity = null;
      }
    }

    final criteria = SearchCriteria(
      minPrice: double.tryParse(_minPriceCtrl.text),
      maxPrice: double.tryParse(_maxPriceCtrl.text),
      minAreaM2: double.tryParse(_minAreaCtrl.text),
      voivodeship: resolvedCity?.voivodeship ?? _selectedVoivodeship,
      rooms: _selectedRooms,
      propertyType: _selectedType,
      cityName: resolvedCity?.name ?? cityPart,
      olxCityId: resolvedCity?.olxCityId,
      locationQuery: districtPart ?? rawLocation,
    );

    final outcomes = await Future.wait([
      ..._portals.map((p) => _safeSearch(p, criteria)),
      _safeSearch(_nol, criteria),
    ]);
    final mainOutcomes = outcomes.sublist(0, _portals.length);
    final nolOutcome = outcomes.last;

    final results = <PropertyListing>[];
    final errors = <String>[];
    for (final outcome in mainOutcomes) {
      if (outcome is _PortalError) {
        errors.add('${outcome.portalName}: ${outcome.error}');
      } else {
        results.addAll(outcome as List<PropertyListing>);
      }
    }
    final nolResults = nolOutcome is _PortalError ? <PropertyListing>[] : nolOutcome as List<PropertyListing>;
    if (nolOutcome is _PortalError) {
      errors.add('${nolOutcome.portalName}: ${nolOutcome.error}');
    }

    setState(() {
      _results = results;
      _nolResults = nolResults;
      _error = errors.isEmpty ? null : errors.join('\n');
      _loading = false;
    });
  }

  Widget _buildResultsList(List<PropertyListing> results) {
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final l = results[i];
        return ListTile(
          leading: l.photoUrls.isNotEmpty
              ? Image.network(l.photoUrls.first, width: 64, height: 64, fit: BoxFit.cover)
              : const Icon(Icons.home, size: 40),
          title: Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '[${l.portal}] ${l.price?.toStringAsFixed(0) ?? '?'} zł · ${l.areaM2 ?? '?'} m² · '
            '${l.rooms ?? '?'} pok. · ${l.city}${l.district != null ? '/${l.district}' : ''}',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HouseHunter'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'OLX + Otodom'),
              Tab(text: 'Nieruchomości-online (${_nolResults.length})'),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SegmentedButton<PropertyType>(
                    segments: const [
                      ButtonSegment(value: PropertyType.flat, label: Text('Mieszkanie'), icon: Icon(Icons.apartment)),
                      ButtonSegment(value: PropertyType.house, label: Text('Dom'), icon: Icon(Icons.house)),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (s) => setState(() => _selectedType = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cena od (zł)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Cena do (zł)'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAreaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Powierzchnia od (m²)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<Voivodeship?>(
                          initialValue: _selectedVoivodeship,
                          decoration: const InputDecoration(labelText: 'Województwo'),
                          items: [
                            const DropdownMenuItem(value: null, child: Text('Cała Polska')),
                            ...Voivodeship.values.map(
                              (v) => DropdownMenuItem(value: v, child: Text(v.displayName)),
                            ),
                          ],
                          onChanged: (v) => setState(() => _selectedVoivodeship = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Miejscowość, dzielnica (opcjonalnie)',
                      hintText: 'np. Warszawa, Mokotów',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: RoomCount.values.map((r) {
                      final label = switch (r) {
                        RoomCount.one => '1 pokój',
                        RoomCount.two => '2 pokoje',
                        RoomCount.three => '3 pokoje',
                        RoomCount.four => '4+',
                      };
                      return FilterChip(
                        label: Text(label),
                        selected: _selectedRooms.contains(r),
                        onSelected: (sel) => setState(
                          () => sel ? _selectedRooms.add(r) : _selectedRooms.remove(r),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _runSearch,
                      child: _loading
                          ? const SizedBox(
                              height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Szukaj'),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildResultsList(_results),
                  _buildResultsList(_nolResults),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalError {
  final String portalName;
  final Object error;

  _PortalError(this.portalName, this.error);
}
