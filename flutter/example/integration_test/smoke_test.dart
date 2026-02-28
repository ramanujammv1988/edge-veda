import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:edge_veda_example/main.dart' as app;
import 'package:flutter/material.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Smoke Tests', () {
    // Smoke test: verifies app launches without crash. Device-specific tests require physical hardware.
    testWidgets('app launches without crashing', (WidgetTester tester) async {
      // Pump the example app's main widget
      app.main();
      await tester.pumpAndSettle();

      // Verify that MaterialApp is present (app successfully launched)
      expect(find.byType(MaterialApp), findsOneWidget);

      // Verify no uncaught exceptions occurred during launch
      // The test will fail if there were any errors during pump
    });

    testWidgets('app shows home screen', (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle();

      // The example app should render without crashing
      // We're not testing specific functionality here, just that the widget tree builds
      expect(tester.takeException(), isNull);
    });
  });
}
