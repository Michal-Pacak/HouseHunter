const _diacriticsFrom = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';
const _diacriticsTo = 'acelnoszzACELNOSZZ';

/// Replaces Polish diacritics with their plain-ASCII equivalents, e.g.
/// "Wesoła" -> "Wesola". Used to compare user-typed place names against
/// portal data case/diacritic-insensitively, and to build URL slugs.
String stripDiacritics(String input) {
  final buffer = StringBuffer();
  for (final ch in input.split('')) {
    final idx = _diacriticsFrom.indexOf(ch);
    buffer.write(idx >= 0 ? _diacriticsTo[idx] : ch);
  }
  return buffer.toString();
}

/// Lowercased, diacritic-stripped form for loose text comparisons.
String normalizeForCompare(String input) => stripDiacritics(input).toLowerCase().trim();

/// A URL-safe slug in the style Otodom uses for its location path segments,
/// e.g. "Stara Miłosna" -> "stara-milosna".
String slugify(String input) {
  final ascii = stripDiacritics(input).toLowerCase();
  final dashed = ascii.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return dashed.replaceAll(RegExp(r'^-+|-+$'), '');
}
