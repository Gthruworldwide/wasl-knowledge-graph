import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_app/data/ai_consent.dart';
import 'package:wasl_app/data/ai_models.dart';
import 'package:wasl_app/data/hosted_ai.dart';

const String _key = 'runtime-only-test-key';

AiPayload _payload({String number = '75000'}) => AiPayload(
  expert: AiExpertKind.equationTutor,
  question: 'ما النتيجة؟',
  claims: [
    <String, Object?>{
      'kind': 'computedResult',
      'text_ar': 'نتيجة محسوبة: $number',
      'text_en': 'Computed result: $number',
      'citations': <Object?>[
        <String, Object?>{'label': 'catalog', 'uri': 'catalog://wasl/equations/x'},
      ],
    },
  ],
);

String _completion(String content) => jsonEncode(<String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'role': 'assistant', 'content': content},
    },
  ],
});

void main() {
  group('HostedAiSettings', () {
    test('toJson redacts the key and chat URL stays key-free', () {
      const settings = HostedAiSettings(apiKey: _key, model: 'gpt-4o-mini');
      expect(settings.isConfigured, isTrue);
      expect(settings.toJson()['api_key'], '[REDACTED]');
      expect(jsonEncode(settings.toJson()), isNot(contains(_key)));
      expect(settings.chatUri().toString(), isNot(contains(_key)));
      expect(settings.chatUri().path, '/v1/chat/completions');
      expect(const HostedAiSettings().isConfigured, isFalse);
    });

    test('store persists runtime settings on-device and clears them', () async {
      SharedPreferences.setMockInitialValues({});
      const store = HostedAiSettingsStore();
      expect((await store.load()).isConfigured, isFalse);

      const settings = HostedAiSettings(apiKey: _key);
      await store.save(settings);
      final loaded = await store.load();
      expect(loaded.apiKey, _key);
      expect(loaded.model, settings.model);
      expect(loaded.baseUrl, settings.baseUrl);

      expect(
        () => store.save(const HostedAiSettings(apiKey: _key, model: '')),
        throwsArgumentError,
      );
      await store.clear();
      expect((await store.load()).isConfigured, isFalse);
    });
  });

  group('HostedAiTextGuard', () {
    const guard = HostedAiTextGuard();

    test('accepts only numbers already present in the payload', () {
      final payload = _payload();
      expect(guard.validate('النتيجة 75000 كما حُسبت', payload), contains('75000'));
      expect(
        () => guard.validate('النتيجة 999999', payload),
        throwsA(isA<AiHostedOutputRejected>().having(
          (error) => error.reason,
          'reason',
          contains('unsupported_numbers'),
        )),
      );
      expect(() => guard.validate('   ', payload), throwsA(isA<AiHostedOutputRejected>()));
    });

    test('normalizes Arabic-Indic digits and comma decimals', () {
      final payload = _payload(number: '12.5');
      expect(guard.validate('القيمة ١٢٫٥', payload), contains('١٢٫٥'));
      expect(
        () => guard.validate('القيمة 13.5', payload),
        throwsA(isA<AiHostedOutputRejected>()),
      );
    });
  });

  group('HttpHostedAiTransport', () {
    test('sends the key only in Authorization and parses the response', () async {
      final requests = <http.Request>[];
      final transport = HttpHostedAiTransport(
        settingsProvider: () async => const HostedAiSettings(apiKey: _key),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            _completion('النتيجة 75000'),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );

      final text = await transport.generate(_payload());
      expect(text, contains('75000'));
      expect(requests.single.headers['Authorization'], 'Bearer $_key');
      expect(requests.single.url.toString(), isNot(contains(_key)));
      expect(requests.single.body, isNot(contains(_key)));
      expect(requests.single.headers['apikey'], isNull);
    });

    test('scrubs the key from errors and refuses without settings', () async {
      final transport = HttpHostedAiTransport(
        settingsProvider: () async => const HostedAiSettings(apiKey: _key),
        client: MockClient(
          (_) async => http.Response('rejected key $_key', 401),
        ),
      );
      await expectLater(
        transport.generate(_payload()),
        throwsA(
          isA<AiHostedApiException>().having(
            (error) => error.message,
            'message',
            allOf(isNot(contains(_key)), contains('[REDACTED]')),
          ),
        ),
      );

      final disabled = HttpHostedAiTransport(
        settingsProvider: () async => const HostedAiSettings(),
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(disabled.generate(_payload()), throwsA(isA<AiHostedDisabled>()));
    });
  });

  group('AiConsentManager hosted flow', () {
    test('stores guarded text and clears it on revoke', () async {
      final manager = AiConsentManager(
        hostedEnabled: true,
        transport: HttpHostedAiTransport(
          settingsProvider: () async => const HostedAiSettings(apiKey: _key),
          client: MockClient(
            (_) async => http.Response(
              _completion('النتيجة 75000'),
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            ),
          ),
        ),
      );
      expect(manager.hostedAvailable, isTrue);
      manager.grantConsent();
      final text = await manager.sendToHosted(_payload());
      expect(text, contains('75000'));
      expect(manager.lastHostedText, text);

      manager.revokeConsent();
      expect(manager.lastHostedText, isNull);
      expect(manager.sessionPayload, isNull);
    });

    test('a foreign number is rejected before any text is stored', () async {
      final manager = AiConsentManager(
        hostedEnabled: true,
        transport: HttpHostedAiTransport(
          settingsProvider: () async => const HostedAiSettings(apiKey: _key),
          client: MockClient(
            (_) async => http.Response(
              _completion('النتيجة 999999'),
              200,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            ),
          ),
        ),
      );
      manager.grantConsent();
      await expectLater(
        manager.sendToHosted(_payload()),
        throwsA(isA<AiHostedOutputRejected>()),
      );
      expect(manager.lastHostedText, isNull);
    });
  });
}
