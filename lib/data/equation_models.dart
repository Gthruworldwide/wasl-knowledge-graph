import 'dart:math' as math;

/// Units used by the reviewed equation catalog.
enum EquationUnit { currency, percent, ratio, price, indexValue, count }

/// Provenance label required for every data row by WASL_FINANCIAL_AI_SPEC.md.
enum EquationSourceKind { live, cached, synthetic, manual }

bool isRealMarketData(EquationSourceKind kind) =>
    kind == EquationSourceKind.live || kind == EquationSourceKind.cached;

extension EquationUnitX on EquationUnit {
  String get wireName => name;
}

extension EquationSourceKindX on EquationSourceKind {
  String get wireName => name;
}

class EquationPeriod {
  final String label;
  final DateTime? start;

  const EquationPeriod({required this.label, this.start});
}

class MetricInput {
  final double? value;
  final EquationUnit unit;
  final String? currency;
  final EquationPeriod? period;
  final EquationSourceKind sourceKind;
  final String? source;
  final bool estimated;

  const MetricInput({
    required this.value,
    required this.unit,
    this.currency,
    this.period,
    this.sourceKind = EquationSourceKind.manual,
    this.source,
    this.estimated = false,
  });
}

class MetricResult {
  final String id;
  final double? value;
  final EquationUnit unit;
  final String? currency;
  final EquationPeriod? period;
  final bool defined;
  final String? reason;
  final String? qualifier;
  final EquationSourceKind sourceKind;

  const MetricResult({
    required this.id,
    required this.value,
    required this.unit,
    required this.defined,
    required this.sourceKind,
    this.currency,
    this.period,
    this.reason,
    this.qualifier,
  });

  String get display {
    if (!defined || value == null) return 'غير متاح';
    final number = value!;
    final digits = number.abs() >= 1000 ? 2 : 4;
    final text = number.toStringAsFixed(digits);
    return unit == EquationUnit.percent ? '$text%' : text;
  }
}

class GradedAnswer {
  final double reference;
  final double learner;
  final double tolerance;
  final bool correct;
  final List<String> steps;
  final String note;

  const GradedAnswer({
    required this.reference,
    required this.learner,
    required this.tolerance,
    required this.correct,
    required this.steps,
    required this.note,
  });
}

class InputSpec {
  final String name;
  final EquationUnit unit;
  final String source;
  final String frequency;

  const InputSpec({
    required this.name,
    required this.unit,
    required this.source,
    required this.frequency,
  });
}

class EquationSpec {
  final String id;
  final String nameAr;
  final String nameEn;
  final String domain;
  final String formula;
  final Map<String, String> symbols;
  final List<InputSpec> inputs;
  final EquationUnit unit;
  final String currencyPolicy;
  final List<String> validity;
  final List<String> edgeCases;
  final String workedExample;
  final double expectedOutput;
  final double tolerance;
  final String reference;
  final String version;

  const EquationSpec({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    required this.domain,
    required this.formula,
    required this.symbols,
    required this.inputs,
    required this.unit,
    required this.currencyPolicy,
    required this.validity,
    required this.edgeCases,
    required this.workedExample,
    required this.expectedOutput,
    required this.tolerance,
    required this.reference,
    required this.version,
  });
}

double roundTo(double value, int digits) {
  final factor = math.pow(10, digits).toDouble();
  return (value * factor).roundToDouble() / factor;
}
