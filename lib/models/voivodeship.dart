/// Portal-agnostic Polish voivodeship. Each adapter maps this onto its own
/// region identifier scheme (OLX: numeric `region_id`; Otodom: URL slug).
enum Voivodeship {
  dolnoslaskie,
  kujawskoPomorskie,
  lubelskie,
  lubuskie,
  lodzkie,
  malopolskie,
  mazowieckie,
  opolskie,
  podkarpackie,
  podlaskie,
  pomorskie,
  slaskie,
  swietokrzyskie,
  warminskoMazurskie,
  wielkopolskie,
  zachodniopomorskie,
}

extension VoivodeshipInfo on Voivodeship {
  String get displayName => switch (this) {
        Voivodeship.dolnoslaskie => 'Dolnośląskie',
        Voivodeship.kujawskoPomorskie => 'Kujawsko-pomorskie',
        Voivodeship.lubelskie => 'Lubelskie',
        Voivodeship.lubuskie => 'Lubuskie',
        Voivodeship.lodzkie => 'Łódzkie',
        Voivodeship.malopolskie => 'Małopolskie',
        Voivodeship.mazowieckie => 'Mazowieckie',
        Voivodeship.opolskie => 'Opolskie',
        Voivodeship.podkarpackie => 'Podkarpackie',
        Voivodeship.podlaskie => 'Podlaskie',
        Voivodeship.pomorskie => 'Pomorskie',
        Voivodeship.slaskie => 'Śląskie',
        Voivodeship.swietokrzyskie => 'Świętokrzyskie',
        Voivodeship.warminskoMazurskie => 'Warmińsko-mazurskie',
        Voivodeship.wielkopolskie => 'Wielkopolskie',
        Voivodeship.zachodniopomorskie => 'Zachodniopomorskie',
      };

  /// OLX `region_id`, determined empirically — see olx_adapter.dart.
  int get olxRegionId => switch (this) {
        Voivodeship.wielkopolskie => 1,
        Voivodeship.mazowieckie => 2,
        Voivodeship.dolnoslaskie => 3,
        Voivodeship.malopolskie => 4,
        Voivodeship.pomorskie => 5,
        Voivodeship.slaskie => 6,
        Voivodeship.lodzkie => 7,
        Voivodeship.lubelskie => 8,
        Voivodeship.lubuskie => 9,
        Voivodeship.zachodniopomorskie => 11,
        Voivodeship.opolskie => 12,
        Voivodeship.swietokrzyskie => 13,
        Voivodeship.warminskoMazurskie => 14,
        Voivodeship.kujawskoPomorskie => 15,
        Voivodeship.podkarpackie => 17,
        Voivodeship.podlaskie => 18,
      };

  /// Otodom URL path slug — confirmed by requesting
  /// `otodom.pl/pl/wyniki/sprzedaz/mieszkanie/<slug>` and checking the
  /// echoed `filteringQueryParams.locations` in the embedded page JSON.
  /// Note the double hyphen in the two compound names — a single hyphen
  /// (or none) 404s; Otodom's own slugs really are "kujawsko--pomorskie"
  /// and "warminsko--mazurskie".
  String get otodomSlug => switch (this) {
        Voivodeship.dolnoslaskie => 'dolnoslaskie',
        Voivodeship.kujawskoPomorskie => 'kujawsko--pomorskie',
        Voivodeship.lubelskie => 'lubelskie',
        Voivodeship.lubuskie => 'lubuskie',
        Voivodeship.lodzkie => 'lodzkie',
        Voivodeship.malopolskie => 'malopolskie',
        Voivodeship.mazowieckie => 'mazowieckie',
        Voivodeship.opolskie => 'opolskie',
        Voivodeship.podkarpackie => 'podkarpackie',
        Voivodeship.podlaskie => 'podlaskie',
        Voivodeship.pomorskie => 'pomorskie',
        Voivodeship.slaskie => 'slaskie',
        Voivodeship.swietokrzyskie => 'swietokrzyskie',
        Voivodeship.warminskoMazurskie => 'warminsko--mazurskie',
        Voivodeship.wielkopolskie => 'wielkopolskie',
        Voivodeship.zachodniopomorskie => 'zachodniopomorskie',
      };
}
