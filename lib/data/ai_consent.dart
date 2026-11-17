import 'ai_models.dart';

class SanitizedPayload {
  final AiPayload payload;
  final List<String> redacted;

  const SanitizedPayload({required this.payload, required this.redacted});
}

/// Defense in depth: even an allowlisted payload is scrubbed before any
/// optional hosted transfer. API keys are never part of [AiPayload].
class AiPayloadSanitizer {
  const AiPayloadSanitizer();

  static const _sensitiveKeys = <String>{
    'apikey',
    'api_key',
    'key',
    'token',
    'access_token',
    'secret',
    'authorization',
    'password',
    'credential',
  };

  static const _sensitiveUriFragments = <String>[
    'apikey=',
    'api_key=',
    'token=',
    'access_token=',
    'secret=',
    'authorization=',
  ];

  static final RegExp _inlineSecret = RegExp(
    r'([?&](?:apikey|api_key|token|access_token|secret)=)[^&\s]+',
    caseSensitive: false,
  );

  SanitizedPayload sanitize(AiPayload payload) {
    final redacted = <String>[];
    final claims = <ClaimView>[];

    for (final claim in payload.claims) {
      final clean = <String, Object?>{};
      claim.forEach((key, value) {
        if (_sensitiveKeys.contains(key.toLowerCase())) {
          redacted.add(key);
          return;
        }
        if (value is String) {
          clean[key] = value.replaceAllMapped(
            _inlineSecret,
            (match) => '${match.group(1)}[REDACTED]',
          );
          return;
        }
        if (key == 'citations' && value is List) {
          clean[key] = [
            for (final item in value)
              if (item is Map) _cleanCitation(item, redacted),
          ];
          return;
        }
        clean[key] = value;
      });
      claims.add(clean);
    }

    return SanitizedPayload(
      payload: AiPayload(
        expert: payload.expert,
        question: payload.question.replaceAllMapped(
          _inlineSecret,
          (match) => '${match.group(1)}[REDACTED]',
        ),
        claims: claims,
      ),
      redacted: redacted,
    );
  }

  Map<String, Object?> _cleanCitation(Map<dynamic, dynamic> citation, List<String> redacted) {
    final clean = Map<String, Object?>.from(citation);
    final uri = clean['uri'];
    if (uri is String &&
        _sensitiveUriFragments.any(
          (fragment) => uri.toLowerCase().contains(fragment),
        )) {
      redacted.add('citation_uri');
      clean['uri'] = 'redacted://';
    }
    return clean;
  }
}

/// Consent is session-scoped and in memory only: nothing is persisted and
/// revoking immediately clears the session payload.
class AiConsentManager {
  AiConsentManager({HostedAiTransport? transport})
      : _transport = transport ?? const DisabledHostedAiTransport();

  final HostedAiTransport _transport;
  bool _consentGranted = false;
  AiPayload? _sessionPayload;

  bool get hasConsent => _consentGranted;

  /// Hard gate. Enabling requires the review recorded in WASL_AI_REVIEW.md.
  bool get hostedAvailable => false;

  AiPayload? get sessionPayload => _sessionPayload;

  void grantConsent() => _consentGranted = true;

  void revokeConsent() {
    _consentGranted = false;
    clearSessionData();
  }

  void clearSessionData() => _sessionPayload = null;

  SanitizedPayload preview(AiPayload payload) {
    final sanitized = const AiPayloadSanitizer().sanitize(payload);
    _sessionPayload = sanitized.payload;
    return sanitized;
  }

  Future<String> sendToHosted(AiPayload payload) async {
    if (!_consentGranted) throw const AiConsentRequired();
    if (!hostedAvailable) throw const AiHostedDisabled();
    final sanitized = const AiPayloadSanitizer().sanitize(payload);
    _sessionPayload = sanitized.payload;
    return _transport.generate(sanitized.payload);
  }
}
