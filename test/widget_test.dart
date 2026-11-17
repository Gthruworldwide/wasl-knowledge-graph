import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts as a clean general-purpose Wasl app', (tester) async {
    await tester.pumpWidget(const WaslApp());
    await tester.pumpAndSettle();

    expect(find.text('وصل'), findsOneWidget);
    expect(
      find.text('ابدأ مساحة معرفتك بإضافة أول كيان ومصدره.'),
      findsOneWidget,
    );
    expect(find.textContaining('Football'), findsNothing);
    expect(find.text('إضافة كيان'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('shows the floating add action after the graph has an entity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'wasl_graph_v1': jsonEncode({
        'entities': [
          {
            'id': 'local-person-1',
            'name': 'Alex Rivera',
            'type': 'person',
            'source_uri': 'https://example.test/people/alex',
            'created_at': '2026-01-01T00:00:00Z',
          },
        ],
        'facts': [],
        'relationships': [],
      }),
    });

    await tester.pumpWidget(const WaslApp());
    await tester.pumpAndSettle();

    expect(
      find.text('ابدأ مساحة معرفتك بإضافة أول كيان ومصدره.'),
      findsNothing,
    );
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Alex Rivera'), findsOneWidget);
  });
}
