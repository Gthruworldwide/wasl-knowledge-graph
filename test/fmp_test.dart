import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/fmp_client.dart';
import 'package:wasl_app/data/fmp_context.dart';
import 'package:wasl_app/data/imf_repository.dart';
import 'package:wasl_app/data/wealth_database.dart';

const String _sampleCpi = '''
[
  {"name":"CPI","date":"2026-10-01","value":337.476},
  {"name":"CPI","date":"2026-09-01","value":336.298}
]
''';

const String _testKey = 'unit-test-key';

MockClient _routingClient(List<Uri> requests) => MockClient((request) async {
  requests.add(request.url);
  expect(request.headers['apikey'], _testKey);
  expect(request.url.queryParameters.containsKey('apikey'), isFalse);
  if (request.url.path.endsWith('/economic-indicators')) {
    return http.Response(
      _sampleCpi,
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
  if (request.url.path.endsWith('/quote')) {
    final symbol = request.url.queryParameters['symbol'] ?? '^GSPC';
    final labels = <String, String>{
      '^GSPC': 'S&P 500',
      '^IXIC': 'NASDAQ Composite',
      '^DJI': 'Dow Jones Industrial Average',
      'GLD': 'Gold ETF',
      'SLV': 'Silver ETF',
      'BTCUSD': 'Bitcoin',
      'ETHUSD': 'Ethereum',
    };
    return http.Response(
      jsonEncode(<Object?>[
        <String, Object?>{
          'symbol': symbol,
          'name': labels[symbol] ?? symbol,
          'price': 100.0,
          'change': 1.0,
          'changePercentage': 1.25,
          'timestamp': 1794941633,
        },
      ]),
      200,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
  return http.Response('unexpected endpoint', 404);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('FmpClient', () {
    test('builds key-free URLs and sends the key in a header', () async {
      final requests = <Uri>[];
      final client = FmpClient(client: _routingClient(requests), apiKey: _testKey);

      final points = await client.fetchEconomicIndicator('CPI');
      expect(points, hasLength(2));
      expect(points.first.value, closeTo(337.476, 0.0001));
      expect(requests.single.path, '/stable/economic-indicators');
      expect(requests.single.queryParameters, <String, String>{'name': 'CPI'});
      expect(requests.single.toString(), isNot(contains(_testKey)));

      final quoteUri = client.quoteUri(symbol: '^GSPC');
      expect(quoteUri.queryParameters['symbol'], '^GSPC');
      expect(quoteUri.toString(), isNot(contains('apikey')));
      expect(quoteUri.toString(), isNot(contains(_testKey)));
    });

    test('parses quote arrays and tolerates empty results', () async {
      final client = FmpClient(
        client: MockClient((request) async {
          if (request.url.queryParameters['symbol'] == '^DJI') {
            return http.Response('[]', 200);
          }
          return http.Response(
            jsonEncode(<Object?>[
              <String, Object?>{
                'symbol': '^IXIC',
                'name': 'NASDAQ Composite',
                'price': 24219.605,
                'change': -290.153,
                'changePercentage': -1.18383,
                'timestamp': 1794941725,
              },
            ]),
            200,
          );
        }),
        apiKey: _testKey,
      );

      final quote = await client.fetchQuote('^IXIC');
      expect(quote, isNotNull);
      expect(quote!.symbol, '^IXIC');
      expect(quote.price, closeTo(24219.605, 0.0001));
      expect(quote.changePercentage, closeTo(-1.18383, 0.0001));
      expect(await client.fetchQuote('^DJI'), isNull);
    });

    test('scrubs the key from errors and rejects a missing key', () async {
      final client = FmpClient(
        client: MockClient(
          (_) async => http.Response('rejected $_testKey', 401),
        ),
        apiKey: _testKey,
      );
      expect(
        () => client.fetchEconomicIndicator('CPI'),
        throwsA(
          isA<FmpApiException>()
              .having((error) => error.statusCode, 'statusCode', 401)
              .having(
                (error) => error.message,
                'message',
                allOf(isNot(contains(_testKey)), contains('[REDACTED]')),
              ),
        ),
      );

      final withoutKey = FmpClient(
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(
        () => withoutKey.fetchQuote('^GSPC'),
        throwsArgumentError,
      );
    });
  });

  group('FMP repository cache', () {
    Future<WealthDatabase> newDatabase() async {
      final database = WealthDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await database.database;
      return database;
    }

    test('caches FMP context idempotently without persisting the key',
        () async {
      SharedPreferences.setMockInitialValues({});
      final database = await newDatabase();
      addTearDown(database.close);
      final requests = <Uri>[];
      final repository = ImfRepository(
        database,
        fmpClient: FmpClient(client: _routingClient(requests), apiKey: _testKey),
        preferences: await SharedPreferences.getInstance(),
      );

      final tables = await (await database.database).rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      expect(
        tables.map((row) => row['name']),
        contains('fmp_market_context'),
      );

      expect(await repository.hasFmpApiKey(), isFalse);
      expect(() => repository.syncFmpContext(), throwsStateError);

      await repository.saveFmpApiKey(_testKey);
      expect(await repository.loadFmpApiKey(), _testKey);

      final expectedQuotes = 1 + fmpAllQuoteSymbols.length;
      final summary = await repository.syncFmpContext();
      expect(summary.rowCount, expectedQuotes);
      expect(summary.errors, isEmpty);
      expect(requests, hasLength(expectedQuotes));
      expect(
        requests.every((uri) => !uri.toString().contains(_testKey)),
        isTrue,
      );

      final cpi = await repository.fmpContext(kind: FmpContextKind.cpi);
      expect(cpi, hasLength(1));
      expect(cpi.single.period, '2026-10-01');
      expect(cpi.single.value, closeTo(337.476, 0.0001));
      expect(cpi.single.sourceUrl, contains('/stable/economic-indicators'));
      expect(cpi.single.sourceUrl, isNot(contains(_testKey)));

      final quotes =
          await repository.fmpContext(kind: FmpContextKind.indexQuote);
      expect(quotes, hasLength(3));
      expect(quotes.every((row) => row.changePercent == 1.25), isTrue);
      expect(
        quotes.every((row) => row.sourceUrl.contains('/stable/quote')),
        isTrue,
      );

      final second = await repository.syncFmpContext();
      expect(second.rowCount, expectedQuotes);
      final rows = await (await database.database).query('fmp_market_context');
      expect(rows, hasLength(expectedQuotes));

      await repository.clearFmpApiKey();
      expect(await repository.hasFmpApiKey(), isFalse);
      expect(() => repository.syncFmpContext(), throwsStateError);
      expect(await repository.fmpContext(), hasLength(expectedQuotes));
    });
  });
}
