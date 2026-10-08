import 'package:flutter_test/flutter_test.dart';

import 'package:househunter/main.dart';

void main() {
  testWidgets('search screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(const HouseHunterApp());

    expect(find.text('Szukaj'), findsOneWidget);
    expect(find.text('Cena od (zł)'), findsOneWidget);
  });
}
