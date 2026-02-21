// Widget test for Edge Veda Example App
//
// This tests that the app can be instantiated and the basic UI is displayed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edge_veda_example/main.dart';

void main() {
  testWidgets('EdgeVedaExampleApp builds and shows initial UI',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const EdgeVedaExampleApp());

    // Verify that the app title is present.
    expect(find.text('Veda'), findsOneWidget);

    // Verify basic UI structure is present.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
