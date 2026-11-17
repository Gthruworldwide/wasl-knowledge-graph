import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_app/data/equation_catalog.dart';
import 'package:wasl_app/data/equation_engine.dart';
import 'package:wasl_app/data/equation_exercises.dart';
import 'package:wasl_app/data/equation_models.dart';
import 'package:wasl_app/presentation/equation_training_page.dart';

MetricInput _m(
  double? value, {
  EquationUnit unit = EquationUnit.currency,
  String? currency,
  EquationPeriod? period,
  bool estimated = false,
  EquationSourceKind sourceKind = EquationSourceKind.manual,
  String? source,
}) =>
    MetricInput(
      value: value,
      unit: unit,
      currency: currency,
      period: period,
      estimated: estimated,
      sourceKind: sourceKind,
      source: source,
    );

void main() {
  test('catalog has 18 scalar specs with reviewed metadata', () {
    expect(equationCatalog, hasLength(18));
    for (final spec in equationCatalog) {
      expect(spec.formula, isNotEmpty, reason: spec.id);
      expect(spec.symbols, isNotEmpty, reason: spec.id);
      expect(spec.inputs, isNotEmpty, reason: spec.id);
      expect(spec.validity, isNotEmpty, reason: spec.id);
      expect(spec.edgeCases, isNotEmpty, reason: spec.id);
      expect(spec.workedExample, isNotEmpty, reason: spec.id);
      expect(spec.reference, startsWith('WASL_FINANCIAL_AI_SPEC.md'), reason: spec.id);
      expect(spec.version, '1.0.0', reason: spec.id);
      expect(spec.tolerance, greaterThanOrEqualTo(0), reason: spec.id);
      expect(spec.expectedOutput, isA<double>(), reason: spec.id);
      expect(equationSpecById(spec.id).id, spec.id);
    }
    expect(() => equationSpecById('does.not.exist'), throwsArgumentError);
  });

  test('exercises cover every spec and reproduce the catalog reference', () {
    expect(equationExercises, hasLength(18));
    expect(
      equationExercises.map((e) => e.specId).toSet(),
      equationCatalog.map((s) => s.id).toSet(),
    );
    for (final exercise in equationExercises) {
      final spec = equationSpecById(exercise.specId);
      final result = EquationEngine.computeById(
        exercise.specId,
        exercise.inputs,
        start: exercise.start,
        end: exercise.end,
      );
      expect(result.defined, isTrue, reason: exercise.specId);
      expect(result.value, isNotNull, reason: exercise.specId);
      expect(
        (result.value! - spec.expectedOutput).abs(),
        lessThanOrEqualTo(spec.tolerance),
        reason: '${exercise.specId}: ${result.value} vs ${spec.expectedOutput}',
      );
      expect(
        exercise.inputs.every((i) => i.sourceKind == EquationSourceKind.synthetic),
        isTrue,
        reason: '${exercise.specId} must be labeled synthetic demo data',
      );
    }
  });

  test('numeric vectors match independent expected values', () {
    const vectors = <String, double>{
      'wealth.net_worth': 75000,
      'wealth.weekly_change_isoweek': 10,
      'wealth.income_source_share': 30,
      'wealth.income_source_hhi': 0.38,
      'business.revenue_growth': 20,
      'business.gross_margin': 40,
      'business.net_margin': 15,
      'business.debt_to_equity': 0.8,
      'business.roi': 30,
      'market.simple_return': 0.1,
      'market.cumulative_return': 0.254,
      'market.cagr': 0.0718,
      'portfolio.expected_return': 0.068,
      'portfolio.annualized_volatility': 0.1629,
      'portfolio.sharpe_ratio': 0.4,
      'portfolio.max_drawdown': -0.25,
      'portfolio.real_return_after_inflation': 0.038835,
      'market.price_change': 5.0,
    };
    for (final exercise in equationExercises) {
      final spec = equationSpecById(exercise.specId);
      final result = EquationEngine.computeById(
        exercise.specId,
        exercise.inputs,
        start: exercise.start,
        end: exercise.end,
      );
      expect(
        (result.value! - vectors[exercise.specId]!).abs(),
        lessThanOrEqualTo(spec.tolerance),
        reason: exercise.specId,
      );
    }
  });

  test('undefined instead of fabricated zero', () {
    final zero = EquationEngine.netMargin(_m(30), _m(0));
    expect(zero.defined, isFalse);
    expect(zero.reason, 'zero_denominator');
    expect(zero.value, isNull);
    expect(zero.display, 'غير متاح');

    final missing = EquationEngine.netWorth(_m(null), _m(10));
    expect(missing.defined, isFalse);
    expect(missing.reason, 'missing_input');
  });

  test('currency, unit, period and model guards reject invalid inputs', () {
    final currency = EquationEngine.netWorth(
      _m(100, currency: 'USD'),
      _m(50, currency: 'EUR'),
    );
    expect(currency.reason, 'incompatible_currency');

    final unit = EquationEngine.netWorth(
      _m(100, unit: EquationUnit.price),
      _m(50),
    );
    expect(unit.reason, 'incompatible_unit');

    final badPeriod = EquationEngine.weeklyChange(
      _m(1100, period: EquationPeriod(label: 'W1', start: DateTime(2026, 11, 9))),
      _m(1000, period: EquationPeriod(label: 'W3', start: DateTime(2026, 10, 26))),
    );
    expect(badPeriod.reason, 'non_consecutive_iso_weeks');

    final weights = EquationEngine.portfolioReturn(
      [
        _m(0.7, unit: EquationUnit.ratio),
        _m(0.4, unit: EquationUnit.ratio),
      ],
      [
        _m(0.08, unit: EquationUnit.ratio),
        _m(0.05, unit: EquationUnit.ratio),
      ],
    );
    expect(weights.reason, 'invalid_weight_sum');

    final short = EquationEngine.annualizedVolatility(
      List.generate(10, (_) => _m(0.01, unit: EquationUnit.ratio)),
    );
    expect(short.reason, 'insufficient_observations');
  });

  test('synthetic and real inputs are never mixed', () {
    final live = _m(100, sourceKind: EquationSourceKind.live, source: 'provider');
    final synthetic = _m(50, sourceKind: EquationSourceKind.synthetic, source: 'demo');
    final result = EquationEngine.netWorth(live, synthetic);
    expect(result.defined, isFalse);
    expect(result.reason, 'mixed_provenance');
  });

  test('result keeps provenance and estimated qualifier', () {
    final result = EquationEngine.incomeShare(
      _m(3000, currency: 'USD', estimated: true, source: 'user'),
      _m(10000, currency: 'USD', source: 'user'),
    );
    expect(result.qualifier, 'estimated');
    expect(result.currency, 'USD');
    expect(result.value, closeTo(30, 1e-9));
    expect(result.sourceKind, EquationSourceKind.manual);
  });

  test('grading uses deterministic reference and declared tolerance', () {
    final exercise = equationExercises.firstWhere(
      (e) => e.specId == 'business.gross_margin',
    );
    final good = EquationEngine.grade(
      id: exercise.specId,
      inputs: exercise.inputs,
      learnerValue: 40.0,
    );
    expect(good.correct, isTrue);
    expect(good.reference, closeTo(40, 1e-9));
    expect(good.steps.join(' '), contains('محرك المعادلات الحتمي'));

    final bad = EquationEngine.grade(
      id: exercise.specId,
      inputs: exercise.inputs,
      learnerValue: 41.0,
    );
    expect(bad.correct, isFalse);

    final loose = EquationEngine.grade(
      id: exercise.specId,
      inputs: exercise.inputs,
      learnerValue: 41.0,
      tolerance: 2.0,
    );
    expect(loose.correct, isTrue);

    expect(
      () => EquationEngine.grade(id: 'unknown.id', inputs: exercise.inputs, learnerValue: 1),
      throwsArgumentError,
    );
  });

  testWidgets('training page labels demo data, shows example and grades answer',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
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
        home: const EquationTrainingPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تدريب المعادلات'), findsOneWidget);
    expect(find.textContaining('وضع تجريبي'), findsOneWidget);
    expect(find.textContaining('مثال معلّم'), findsOneWidget);
    expect(find.text('صافي الثروة'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '75000');
    await tester.tap(find.widgetWithText(ElevatedButton, 'تحقق'));
    await tester.pumpAndSettle();
    expect(find.textContaining('إجابة صحيحة'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'تمرين جديد'));
    await tester.pumpAndSettle();
    expect(find.text('التغير الأسبوعي'), findsOneWidget);
  });
}
