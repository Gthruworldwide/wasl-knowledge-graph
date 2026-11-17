import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_app/data/ai_consent.dart';
import 'package:wasl_app/data/ai_experts.dart';
import 'package:wasl_app/data/ai_grounding.dart';
import 'package:wasl_app/data/ai_models.dart';
import 'package:wasl_app/data/ai_tools.dart';
import 'package:wasl_app/data/equation_catalog.dart';
import 'package:wasl_app/data/equation_exercises.dart';
import 'package:wasl_app/data/equation_models.dart';
import 'package:wasl_app/presentation/ai_explanation_page.dart';

void main() {
  test('claim kinds distinguish sourced, computed, estimate, explanation and unavailable', () {
    expect(ClaimKind.values, hasLength(5));
    expect(ClaimKind.values.map((kind) => kind.label(true)).toSet(), hasLength(5));
    expect(ClaimKind.computedResult.label(false), 'computed result');
    expect(ClaimKind.unavailable.label(false), 'unavailable');
  });

  test('equation explanation labels synthetic inputs and computes from the engine', () {
    final exercise = equationExercises.firstWhere(
      (item) => item.specId == 'wealth.net_worth',
    );
    final response = const AiGroundingEngine().explainEquation(
      equationId: exercise.specId,
      inputs: exercise.inputs,
      start: exercise.start,
      end: exercise.end,
    );

    expect(response.hasEvidence, isTrue);
    expect(response.expert, AiExpertKind.equationTutor);
    final kinds = response.claims.map((claim) => claim.kind).toList();
    expect(kinds, contains(ClaimKind.estimate));
    expect(kinds, contains(ClaimKind.computedResult));
    expect(kinds, contains(ClaimKind.generatedExplanation));
    expect(kinds, isNot(contains(ClaimKind.sourcedValue)));

    final computed = response.claims.firstWhere(
      (claim) => claim.kind == ClaimKind.computedResult,
    );
    expect(computed.text(true), contains('75000'));
    expect(computed.citations.first.uri, contains('catalog://'));
    for (final claim in response.claims.where(
      (claim) => claim.kind == ClaimKind.estimate,
    )) {
      expect(claim.text(true), contains('synthetic'));
      expect(claim.provenance, 'synthetic');
    }
  });

  test('missing or invalid inputs yield unavailable, never a fabricated number', () {
    final response = const AiGroundingEngine().explainEquation(
      equationId: 'business.gross_margin',
      inputs: [
        MetricInput(value: 0, unit: EquationUnit.currency),
        MetricInput(value: 30, unit: EquationUnit.currency),
      ],
    );
    expect(response.hasEvidence, isFalse);
    expect(response.claims, hasLength(1));
    expect(response.claims.single.kind, ClaimKind.unavailable);
    expect(response.claims.single.text(true), contains('zero_denominator'));
  });

  test('metric explainer adds declared policy without inventing numbers', () {
    final exercise = equationExercises.firstWhere(
      (item) => item.specId == 'market.price_change',
    );
    final response = const AiGroundingEngine().explainMetric(
      equationId: exercise.specId,
      inputs: exercise.inputs,
    );
    final spec = equationSpecById(exercise.specId);
    expect(response.expert, AiExpertKind.metricExplainer);
    expect(response.claims.last.text(true), contains(spec.currencyPolicy));
  });

  test('data quality reviewer flags mixed provenance', () {
    final exercise = equationExercises.firstWhere(
      (item) => item.specId == 'wealth.net_worth',
    );
    final response = const AiGroundingEngine().reviewDataQuality(
      inputs: [
        MetricInput(
          value: 100,
          unit: EquationUnit.currency,
          currency: 'USD',
          sourceKind: EquationSourceKind.live,
          source: 'provider',
        ),
        exercise.inputs.last,
      ],
    );
    expect(response.hasEvidence, isFalse);
    expect(response.claims.map((claim) => claim.kind), contains(ClaimKind.unavailable));
  });

  test('grounded retrieval uses only supplied local citations', () {
    const engine = AiGroundingEngine();
    final empty = engine.fromKnowledge(query: 'x', sources: const []);
    expect(empty.hasEvidence, isFalse);
    expect(empty.claims.single.kind, ClaimKind.unavailable);

    final grounded = engine.fromKnowledge(
      query: 'x',
      sources: const [
        KnowledgeCitationSource(label: 'IMF CPI 2026-10', uri: 'https://imf.test/observation'),
      ],
    );
    expect(grounded.hasEvidence, isTrue);
    expect(grounded.claims.single.kind, ClaimKind.sourcedValue);
    expect(grounded.claims.single.citations.single.uri, 'https://imf.test/observation');
  });

  test('tools are typed, read-only and reject writes and arbitrary SQL', () {
    const registry = AiToolRegistry();
    expect(AiToolName.values.every((tool) => !tool.name.toLowerCase().contains('sql')), isTrue);
    expect(registry.isAllowed(AiToolName.writeDatabase), isFalse);

    final write = registry.call(AiToolName.writeDatabase, const {});
    expect(write.ok, isFalse);
    expect(write.reason, 'write_requires_explicit_user_confirmation');

    final spec = registry.call(
      AiToolName.getEquationSpec,
      const {'id': 'business.gross_margin'},
    );
    expect(spec.ok, isTrue);

    final untyped = registry.call(
      AiToolName.computeEquation,
      const {'id': 'business.gross_margin', 'inputs': [1, 2]},
    );
    expect(untyped.reason, 'invalid_typed_inputs');
  });

  test('three functional experts forbid numbers, advice and fatwa', () {
    expect(aiExpertConfigs, hasLength(3));
    for (final config in aiExpertConfigs.values) {
      expect(config.prohibitionsAr.join(' '), contains('لا تحسب أرقامًا بنفسك'));
      expect(config.prohibitionsAr.join(' '), contains('فتوى'));
      expect(config.prohibitionsAr.join(' '), contains('توصية شراء'));
    }
    expect(
      expertConfig(AiExpertKind.equationTutor).allowedTools,
      contains(AiToolName.computeEquation),
    );
    expect(
      expertConfig(AiExpertKind.dataQualityReviewer).allowedTools,
      isNot(contains(AiToolName.computeEquation)),
    );
  });

  test('payload is allowlisted and sanitizer strips key material', () {
    final payload = AiPayload(
      expert: AiExpertKind.equationTutor,
      question: '?apikey=abc123 safe text',
      claims: [
        {
          'kind': 'computedResult',
          'text_ar': '75000',
          'citations': [
            {'label': 'x', 'uri': 'https://example.test/data?apikey=abc123'},
          ],
        },
        {'apiKey': 'should-be-removed', 'text_ar': 'keep'},
      ],
    );
    final preview = const AiPayloadSanitizer().sanitize(payload);
    expect(preview.redacted, contains('apiKey'));
    expect(preview.redacted, contains('citation_uri'));
    final json = jsonEncode(preview.payload.toJson());
    expect(json, isNot(contains('abc123')));
    expect(json, isNot(contains('should-be-removed')));
    expect(json, contains('expert'));
  });

  test('consent is off by default, revocable and hosted transfer stays gated', () async {
    final manager = AiConsentManager();
    const payload = AiPayload(
      expert: AiExpertKind.equationTutor,
      question: 'test',
      claims: [],
    );
    expect(manager.hasConsent, isFalse);
    expect(manager.hostedAvailable, isFalse);
    await expectLater(manager.sendToHosted(payload), throwsA(isA<AiConsentRequired>()));

    manager.preview(payload);
    expect(manager.sessionPayload, isNotNull);

    manager.grantConsent();
    expect(manager.hasConsent, isTrue);
    await expectLater(manager.sendToHosted(payload), throwsA(isA<AiHostedDisabled>()));

    manager.revokeConsent();
    expect(manager.hasConsent, isFalse);
    expect(manager.sessionPayload, isNull);
  });

  testWidgets('AI page explains locally, previews payload and blocks hosted transfer',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AiExplanationPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('الوضع المحلي'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'شرح محلي'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تقدير تجريبي (synthetic)'), findsWidgets);
    expect(find.textContaining('75000'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'مراجعة الإرسال'));
    await tester.pumpAndSettle();
    expect(find.text('ما الذي سيُرسل؟'), findsOneWidget);
    expect(find.textContaining('catalog://'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'إلغاء'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'مراجعة الإرسال'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'موافقة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('غير مُفعّل'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'إزالة الجلسة'));
    await tester.pumpAndSettle();
    expect(find.textContaining('تم إلغاء الموافقة'), findsOneWidget);
  });
}
