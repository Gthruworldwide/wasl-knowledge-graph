import 'ai_models.dart';
import 'equation_catalog.dart';
import 'equation_engine.dart';
import 'equation_models.dart';

const _disclaimersAr = <String>[
  'لا تُقدَّم توصية شراء أو بيع ولا تشخيص مالي أو فتوى.',
  'كل رقم معروض إما قيمة مصدرية أو نتيجة محسوبة بمحرك حتمي أو تقدير معلّم.',
  'البيانات التجريبية (synthetic) ليست أسعار سوق حقيقية ولا تُستخدم في التقارير.',
  'التقديرات التاريخية ليست تنبؤًا بالأداء المستقبلي.',
];

const _disclaimersEn = <String>[
  'No buy/sell recommendation, financial diagnosis or fatwa is provided.',
  'Every number is either a sourced value, a deterministic engine result or a labeled estimate.',
  'Synthetic demo data is not real market data and is never used in reports.',
  'Historical estimates are not forecasts of future performance.',
];

String _fmt(double? value) {
  if (value == null) return 'غير متاح';
  return value.abs() >= 1000
      ? value.toStringAsFixed(2)
      : value.toStringAsFixed(6);
}

/// Builds responses only from catalog specs and deterministic engine results.
/// It never invents a number or a source.
class AiGroundingEngine {
  const AiGroundingEngine();

  GroundedResponse explainEquation({
    required String equationId,
    required List<MetricInput> inputs,
    DateTime? start,
    DateTime? end,
  }) {
    final spec = equationSpecById(equationId);
    final result = EquationEngine.computeById(
      equationId,
      inputs,
      start: start,
      end: end,
    );
    if (!result.defined || result.value == null) {
      return GroundedResponse(
        expert: AiExpertKind.equationTutor,
        claims: [
          GroundedClaim(
            kind: ClaimKind.unavailable,
            textAr: 'غير متاح: تعذّر الحساب (${result.reason ?? 'unknown_reason'}).',
            textEn: 'Unavailable: computation failed (${result.reason ?? 'unknown_reason'}).',
            equationId: equationId,
          ),
        ],
        disclaimersAr: _disclaimersAr,
        disclaimersEn: _disclaimersEn,
        hasEvidence: false,
      );
    }

    final claims = <GroundedClaim>[
      ..._inputClaims(inputs),
      GroundedClaim(
        kind: ClaimKind.computedResult,
        textAr: 'نتيجة محسوبة: ${result.display} — المعادلة $equationId '
            'الإصدار ${spec.version}.',
        textEn: 'Computed result: ${result.display} — equation $equationId '
            'version ${spec.version}.',
        equationId: equationId,
        citations: [
          Citation(
            label: 'catalog:$equationId@${spec.version}',
            uri: 'catalog://wasl/equations/$equationId',
          ),
        ],
      ),
      GroundedClaim(
        kind: ClaimKind.generatedExplanation,
        textAr: 'شرح مولّد ضمن الصيغة المراجعة: ${spec.formula}. الرموز: '
            '${spec.symbols.values.join('، ')}.',
        textEn: 'Generated explanation within the reviewed formula: ${spec.formula}. '
            'Symbols: ${spec.symbols.values.join(', ')}.',
        equationId: equationId,
        citations: [
          Citation(
            label: 'catalog:$equationId@${spec.version}',
            uri: 'catalog://wasl/equations/$equationId',
          ),
        ],
      ),
    ];

    return GroundedResponse(
      expert: AiExpertKind.equationTutor,
      claims: claims,
      disclaimersAr: _disclaimersAr,
      disclaimersEn: _disclaimersEn,
      hasEvidence: true,
    );
  }

  GroundedResponse explainMetric({
    required String equationId,
    required List<MetricInput> inputs,
    DateTime? start,
    DateTime? end,
  }) {
    final base = explainEquation(
      equationId: equationId,
      inputs: inputs,
      start: start,
      end: end,
    );
    final spec = equationSpecById(equationId);
    final extra = GroundedClaim(
      kind: ClaimKind.generatedExplanation,
      textAr: 'سياق القيمة: الوحدة ${spec.unit.wireName}؛ ${spec.currencyPolicy}. '
          'ولا تُقارن إلا عند اتساق العملة والفترة.',
      textEn: 'Value context: unit ${spec.unit.wireName}; ${spec.currencyPolicy}. '
          'Compare only when currency and period are consistent.',
      equationId: equationId,
    );
    return GroundedResponse(
      expert: AiExpertKind.metricExplainer,
      claims: [...base.claims, extra],
      disclaimersAr: _disclaimersAr,
      disclaimersEn: _disclaimersEn,
      hasEvidence: base.hasEvidence,
    );
  }

  GroundedResponse reviewDataQuality({required List<MetricInput> inputs}) {
    final claims = <GroundedClaim>[..._inputClaims(inputs)];
    final real = inputs.where((input) =>
        input.sourceKind == EquationSourceKind.live ||
        input.sourceKind == EquationSourceKind.cached);
    final synthetic = inputs.where(
      (input) => input.sourceKind == EquationSourceKind.synthetic,
    );
    if (real.isNotEmpty && synthetic.isNotEmpty) {
      claims.add(
        GroundedClaim(
          kind: ClaimKind.unavailable,
          textAr: 'غير متاح: خلط بين بيانات حقيقية واصطناعية ممنوع.',
          textEn: 'Unavailable: mixing real and synthetic data is not allowed.',
        ),
      );
    }
    return GroundedResponse(
      expert: AiExpertKind.dataQualityReviewer,
      claims: claims,
      disclaimersAr: _disclaimersAr,
      disclaimersEn: _disclaimersEn,
      hasEvidence: inputs.isNotEmpty && real.isEmpty,
    );
  }

  GroundedResponse fromKnowledge({
    required String query,
    required List<KnowledgeCitationSource> sources,
  }) {
    if (sources.isEmpty) {
      return GroundedResponse(
        expert: AiExpertKind.metricExplainer,
        claims: [
          GroundedClaim(
            kind: ClaimKind.unavailable,
            textAr: 'غير متاح: لا توجد حقائق محلية مطابقة للاستعلام.',
            textEn: 'Unavailable: no matching local facts for the query.',
          ),
        ],
        disclaimersAr: _disclaimersAr,
        disclaimersEn: _disclaimersEn,
        hasEvidence: false,
      );
    }
    return GroundedResponse(
      expert: AiExpertKind.metricExplainer,
      claims: [
        for (final source in sources)
          GroundedClaim(
            kind: ClaimKind.sourcedValue,
            textAr: 'قيمة مصدرية: ${source.label}.',
            textEn: 'Sourced value: ${source.label}.',
            citations: [
              Citation(
                label: source.label,
                uri: source.uri,
                retrievedAt: source.retrievedAt,
              ),
            ],
          ),
      ],
      disclaimersAr: _disclaimersAr,
      disclaimersEn: _disclaimersEn,
      hasEvidence: true,
    );
  }

  List<GroundedClaim> _inputClaims(List<MetricInput> inputs) => [
    for (final input in inputs)
      GroundedClaim(
        kind: (input.estimated ||
                input.sourceKind == EquationSourceKind.synthetic)
            ? ClaimKind.estimate
            : ClaimKind.sourcedValue,
        textAr: '${(input.estimated || input.sourceKind == EquationSourceKind.synthetic) ? 'تقدير تجريبي (synthetic)' : 'قيمة مصدرية'}: '
            '${_fmt(input.value)} ${input.unit.wireName} '
            '(${input.sourceKind.wireName}).',
        textEn: '${(input.estimated || input.sourceKind == EquationSourceKind.synthetic) ? 'Synthetic demo estimate' : 'Sourced value'}: '
            '${_fmt(input.value)} ${input.unit.wireName} '
            '(${input.sourceKind.wireName}).',
        provenance: input.sourceKind.wireName,
        citations: [
          if (input.source != null)
            Citation(
              label: input.source!,
              uri: 'local://wasl/source/${input.source}',
            ),
        ],
      ),
  ];
}

class KnowledgeCitationSource {
  final String label;
  final String uri;
  final String? retrievedAt;

  const KnowledgeCitationSource({
    required this.label,
    required this.uri,
    this.retrievedAt,
  });
}
