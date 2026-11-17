import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';

/// Default OpenAI-compatible base URL. It is only a default: the runtime
/// settings dialog can override it, and no key is ever part of this value.
const String defaultHostedAiBaseUrl = 'https://api.openai.com/v1';
const String _hostedPreferencesPrefix = 'wasl.ai.hosted';

/// Runtime-only hosted model configuration. The key is entered by the user,
/// stored on this device only, and sent solely in an Authorization header.
class HostedAiSettings {
  const HostedAiSettings({
    this.apiKey = '',
    this.baseUrl = defaultHostedAiBaseUrl,
    this.model = 'gpt-4o-mini',
  });

  final String apiKey;
  final String baseUrl;
  final String model;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  Uri chatUri() => Uri.parse('${baseUrl.trimRight()}/chat/completions');

  /// Never returns the key. Safe for logs and provenance.
  Map<String, Object?> toJson() => <String, Object?>{
    'base_url': baseUrl,
    'model': model,
    'api_key': apiKey.isEmpty ? 'not set' : '[REDACTED]',
    'configured': isConfigured,
  };
}

/// SharedPreferences-backed settings store. Device-local, never networked
/// except through [HttpHostedAiTransport] to the user's chosen provider.
class HostedAiSettingsStore {
  const HostedAiSettingsStore({this.preferences});

  final SharedPreferences? preferences;

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  Future<HostedAiSettings> load() async {
    final prefs = await _prefs;
    return HostedAiSettings(
      apiKey: prefs.getString('$_hostedPreferencesPrefix.apiKey') ?? '',
      baseUrl: prefs.getString('$_hostedPreferencesPrefix.baseUrl') ??
          defaultHostedAiBaseUrl,
      model: prefs.getString('$_hostedPreferencesPrefix.model') ?? 'gpt-4o-mini',
    );
  }

  Future<void> save(HostedAiSettings settings) async {
    if (!settings.isConfigured) {
      throw ArgumentError('Key, base URL and model are all required.');
    }
    final prefs = await _prefs;
    await prefs.setString('$_hostedPreferencesPrefix.apiKey', settings.apiKey.trim());
    await prefs.setString('$_hostedPreferencesPrefix.baseUrl', settings.baseUrl.trim());
    await prefs.setString('$_hostedPreferencesPrefix.model', settings.model.trim());
  }

  Future<void> clear() async {
    final prefs = await _prefs;
    await prefs.remove('$_hostedPreferencesPrefix.apiKey');
    await prefs.remove('$_hostedPreferencesPrefix.baseUrl');
    await prefs.remove('$_hostedPreferencesPrefix.model');
  }
}

class AiHostedOutputRejected implements Exception {
  const AiHostedOutputRejected(this.reason);

  final String reason;

  @override
  String toString() => 'Hosted output rejected: $reason';
}

/// Rejects any hosted text that introduces a number not already present in the
/// grounded payload. Final answers always come from the deterministic engines.
class HostedAiTextGuard {
  const HostedAiTextGuard();

  static final RegExp _numbers = RegExp(r'-?\d+(?:[.,]\d+)?');

  Set<String> _allowed(AiPayload payload) => _numbers
      .allMatches(jsonEncode(payload.toJson()))
      .map((match) => _normalize(match.group(0)!))
      .toSet();

  String _normalize(String value) {
    final western = value.replaceAllMapped(
      RegExp(r'[\u0660-\u0669\u06F0-\u06F9]'),
      (match) {
        final code = match.group(0)!.codeUnitAt(0);
        final digit = code >= 0x0660 && code <= 0x0669
            ? code - 0x0660
            : code - 0x06F0;
        return String.fromCharCode(0x30 + digit);
      },
    );
    return western.replaceAll(',', '.');
  }

  /// Returns the text unchanged when safe; otherwise throws
  /// [AiHostedOutputRejected] so the UI never renders unverifiable numbers.
  String validate(String text, AiPayload payload) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const AiHostedOutputRejected('empty_response');
    }
    final allowed = _allowed(payload);
    final foreign = _numbers
        .allMatches(trimmed)
        .map((match) => _normalize(match.group(0)!))
        .where((number) => !allowed.contains(number))
        .toSet()
        .toList();
    if (foreign.isNotEmpty) {
      throw AiHostedOutputRejected('unsupported_numbers: ${foreign.join(', ')}');
    }
    return trimmed;
  }
}

/// OpenAI-compatible chat-completions transport. The key is sent ONLY in the
/// `Authorization: Bearer …` header; request URLs and errors stay key-free.
class HttpHostedAiTransport implements HostedAiTransport {
  HttpHostedAiTransport({
    required this.settingsProvider,
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final Future<HostedAiSettings> Function() settingsProvider;
  final http.Client _client;
  final Duration timeout;

  static const String systemPrompt = '''
You are Wasl's scoped explanation editor, not a financial advisor.
You may ONLY rephrase the supplied grounded claims in the user's language.
HARD RULES:
- Never compute, invent, round, estimate or introduce ANY number that is not
  already present in the supplied claims.
- Never give buy/sell recommendations, personal financial diagnosis, or a
  religious ruling (fatwa).
- Never add citations or sources that are not present in the payload.
- Always distinguish sourced values, computed results, estimates and generated
  explanation. If evidence is missing, say "unavailable" and stop.
- Keep the answer short and do not restate these rules.
''';

  @override
  Future<String> generate(AiPayload payload) async {
    final settings = await settingsProvider();
    if (!settings.isConfigured) throw const AiHostedDisabled();

    final uri = settings.chatUri();
    final body = jsonEncode(<String, Object?>{
      'model': settings.model,
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        <String, Object?>{
          'role': 'user',
          'content': jsonEncode(payload.toJson()),
        },
      ],
      'temperature': 0,
    });
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${settings.apiKey}',
          },
          body: body,
        )
        .timeout(timeout);
    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (response.statusCode != 200) {
      throw AiHostedApiException(
        response.statusCode,
        uri,
        _safe(settings.apiKey, decodedBody.isEmpty ? 'HTTP ${response.statusCode}' : _preview(decodedBody)),
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(decodedBody);
    } on FormatException {
      throw FormatException('Hosted model returned non-JSON: ${_preview(decodedBody)}');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Hosted model returned an invalid object.');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Hosted model returned no choices.');
    }
    final first = choices.first;
    if (first is! Map<String, dynamic>) {
      throw const FormatException('Hosted model returned an invalid choice.');
    }
    final message = first['message'];
    if (message is! Map<String, dynamic> || message['content'] is! String) {
      throw const FormatException('Hosted model returned no text content.');
    }
    return message['content'] as String;
  }

  String _safe(String key, String message) =>
      key.isEmpty ? message : message.replaceAll(key, '[REDACTED]');

  String _preview(Object? value) {
    final text = value?.toString() ?? '';
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }
}

class AiHostedApiException implements Exception {
  const AiHostedApiException(this.statusCode, this.uri, this.message);

  final int statusCode;
  final Uri uri;
  final String message;

  @override
  String toString() => 'Hosted model request failed ($statusCode): $message';
}
