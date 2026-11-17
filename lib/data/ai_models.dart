/// Typed contracts for Wasl's scoped AI layer.
///
/// Nothing here performs network I/O. The coordinator only renders claims that
/// came from local deterministic engines or locally stored sources.
enum ClaimKind {
  sourcedValue,
  computedResult,
  estimate,
  generatedExplanation,
  unavailable;

  String get wireName => name;

  String label(bool isArabic) {
    switch (this) {
      case ClaimKind.sourcedValue:
        return isArabic ? 'قيمة مصدرية' : 'sourced value';
      case ClaimKind.computedResult:
        return isArabic ? 'نتيجة محسوبة' : 'computed result';
      case ClaimKind.estimate:
        return isArabic ? 'تقدير' : 'estimate';
      case ClaimKind.generatedExplanation:
        return isArabic ? 'شرح مولّد' : 'generated explanation';
      case ClaimKind.unavailable:
        return isArabic ? 'غير متاح' : 'unavailable';
    }
  }
}

enum AiExpertKind {
  equationTutor,
  metricExplainer,
  dataQualityReviewer;

  String label(bool isArabic) {
    switch (this) {
      case AiExpertKind.equationTutor:
        return isArabic ? 'معلّم المعادلات' : 'Equation tutor';
      case AiExpertKind.metricExplainer:
        return isArabic ? 'شارح المقاييس' : 'Metric explainer';
      case AiExpertKind.dataQualityReviewer:
        return isArabic ? 'مراجع جودة البيانات' : 'Data quality reviewer';
    }
  }
}

enum AiToolName {
  getEquationSpec,
  computeEquation,
  searchKnowledge,
  latestObservation,
  writeDatabase;

  String label(bool isArabic) {
    switch (this) {
      case AiToolName.getEquationSpec:
        return isArabic ? 'قراءة مواصفة معادلة' : 'read equation spec';
      case AiToolName.computeEquation:
        return isArabic ? 'حساب معادلة' : 'compute equation';
      case AiToolName.searchKnowledge:
        return isArabic ? 'بحث في المعرفة المحلية' : 'search local knowledge';
      case AiToolName.latestObservation:
        return isArabic ? 'أحدث مشاهدة CPI' : 'latest CPI observation';
      case AiToolName.writeDatabase:
        return isArabic ? 'كتابة قاعدة البيانات (محظورة)' : 'database write (blocked)';
    }
  }
}

class Citation {
  final String label;
  final String uri;
  final String? retrievedAt;

  const Citation({required this.label, required this.uri, this.retrievedAt});

  Map<String, Object?> toJson() => {
    'label': label,
    'uri': uri,
    if (retrievedAt != null) 'retrieved_at': retrievedAt,
  };
}

class GroundedClaim {
  final ClaimKind kind;
  final String textAr;
  final String textEn;
  final List<Citation> citations;
  final String? equationId;
  final String? provenance;

  const GroundedClaim({
    required this.kind,
    required this.textAr,
    required this.textEn,
    this.citations = const [],
    this.equationId,
    this.provenance,
  });

  String text(bool isArabic) => isArabic ? textAr : textEn;
}

class GroundedResponse {
  final AiExpertKind expert;
  final List<GroundedClaim> claims;
  final List<String> disclaimersAr;
  final List<String> disclaimersEn;
  final bool hasEvidence;

  const GroundedResponse({
    required this.expert,
    required this.claims,
    required this.disclaimersAr,
    required this.disclaimersEn,
    required this.hasEvidence,
  });

  List<String> disclaimers(bool isArabic) =>
      isArabic ? disclaimersAr : disclaimersEn;

  /// Only an allowlisted projection may be sent to a hosted model.
  AiPayload toPayload({required String question}) => AiPayload(
    expert: expert,
    question: question,
    claims: [
      for (final claim in claims)
      if (claim.kind != ClaimKind.unavailable)
        {
          'kind': claim.kind.wireName,
          'text_ar': claim.textAr,
          'text_en': claim.textEn,
          if (claim.equationId != null) 'equation_id': claim.equationId,
          if (claim.provenance != null) 'provenance': claim.provenance,
          'citations': [for (final citation in claim.citations) citation.toJson()],
        },
    ],
  );
}

typedef ClaimView = Map<String, Object?>;

class AiPayload {
  final AiExpertKind expert;
  final String question;
  final List<ClaimView> claims;

  const AiPayload({
    required this.expert,
    required this.question,
    required this.claims,
  });

  Map<String, Object?> toJson() => {
    'expert': expert.name,
    'question': question,
    'claims': claims,
  };
}

class AiToolResult {
  final bool ok;
  final Object? data;
  final String? reason;
  final List<Citation> citations;

  const AiToolResult._({
    required this.ok,
    this.data,
    this.reason,
    this.citations = const [],
  });

  factory AiToolResult.success(Object? data, {List<Citation> citations = const []}) =>
      AiToolResult._(ok: true, data: data, citations: citations);

  factory AiToolResult.failure(String reason) =>
      AiToolResult._(ok: false, reason: reason);
}

class AiConsentRequired implements Exception {
  const AiConsentRequired();

  @override
  String toString() => 'Explicit consent is required before any hosted transfer.';
}

class AiHostedDisabled implements Exception {
  const AiHostedDisabled();

  @override
  String toString() =>
      'Hosted transfer is disabled. Configure a provider with runtime settings first.';
}

abstract class HostedAiTransport {
  const HostedAiTransport();

  /// An optional HTTP transport. It is only reached after runtime provider
  /// settings exist AND the user grants per-request consent. The default
  /// implementation is always disabled.
  Future<String> generate(AiPayload payload);
}

class DisabledHostedAiTransport implements HostedAiTransport {
  const DisabledHostedAiTransport();

  @override
  Future<String> generate(AiPayload payload) async =>
      throw const AiHostedDisabled();
}
