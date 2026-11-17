import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/market_data_client.dart';
import 'package:wasl_app/data/market_data_repository.dart';
import 'package:wasl_app/data/wealth_database.dart';

String _chartResponse({
  required String symbol,
  required double price,
  required double previous,
}) => jsonEncode(<String, Object?>{
  'chart': <String, Object?>{
    'error': null,
    'result': <Object?>[
      <String, Object?>{
        'meta': <String, Object?>{
          'symbol': symbol,
          'shortName': 'Sample $symbol',
          'regularMarketPrice': price,
          'chartPreviousClose': previous,
          'regularMarketTime': 1794941633,
        },
      },
    ],
  },
});

MockClient _chartClient(List<Uri> requests) => MockClient((request) async {
  requests.add(request.url);
  final symbol = request.url.path.split('/').last;
  final price = switch (symbol) {
    'GC=F' => 4200.0,
    'GLD' => 245.0,
    'SLV' => 31.0,
    _ => 0.0,
  };
  if (price == 0.0) return http.Response('not found', 404);
  return http.Response(
    _chartResponse(symbol: symbol, price: price, previous: price / 1.01),
    200,
    headers: <String, String>{'content-type': 'application/json'},
  );
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('MarketDataClient', () {
    test('builds key-free chart URLs and parses GC=F quotes', () async {
      final requests = <Uri>[];
      final client = MarketDataClient(client: _chartClient(requests));
      final quote = await client.fetchQuote(MarketAssetKind.goldFuture);

      expect(quote, isNotNull);
      expect(quote!.symbol, 'GC=F');
      expect(quote.price, closeTo(4200, 0.0001));
      expect(quote.changePercent, closeTo(1.0, 0.0001));
      expect(quote.period, contains('2026'));
      expect(requests.single.path, '/v8/finance/chart/GC=F');
      expect(requests.single.queryParameters, <String, String>{
        'interval': '1d',
        'range': '5d',
      });
      expect(requests.single.toString(), isNot(contains('apikey')));
      expect(client.chartUri('XAUUSD=X').toString(), contains('XAUUSD=X'));
    });

    test('returns null for empty responses and reports HTTP errors', () async {
      final empty = MarketDataClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'chart': <String, Object?>{'result': <Object?>[]},
            }),
            200,
          ),
        ),
      );
      expect(await empty.fetchQuote(MarketAssetKind.goldEtf), isNull);

      final failing = MarketDataClient(
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );
      await expectLater(
        failing.fetchQuote(MarketAssetKind.silverEtf),
        throwsA(isA<MarketDataApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          429,
        )),
      );
    });
  });

  group('MarketDataRepository cache', () {
    Future<WealthDatabase> newDatabase() async {
      final database = WealthDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await database.database;
      return database;
    }

    test('caches all three assets with provenance and key-free URLs', () async {
      final database = await newDatabase();
      addTearDown(database.close);
      final requests = <Uri>[];
      final repository = MarketDataRepository(
        database,
        client: MarketDataClient(client: _chartClient(requests)),
      );

      final summary = await repository.syncMarketData();
      expect(summary.rowCount, 3);
      expect(summary.errors, isEmpty);
      expect(requests, hasLength(3));

      final rows = await repository.latest();
      expect(rows, hasLength(3));
      expect(
        rows.map((row) => row.asset).toSet(),
        MarketAssetKind.values.toSet(),
      );
      expect(rows.every((row) => row.provenance == 'cached'), isTrue);
      expect(rows.every((row) => row.source == 'YAHOO'), isTrue);
      expect(
        rows.every(
          (row) =>
              row.sourceUrl.contains('/v8/finance/chart/') &&
              !row.sourceUrl.contains('apikey'),
        ),
        isTrue,
      );
      expect(
        rows.any((row) => row.symbol == 'XAUUSD=X'),
        isFalse,
      );

      final gold = rows.singleWhere(
        (row) => row.asset == MarketAssetKind.goldFuture,
      );
      expect(gold.value, closeTo(4200, 0.0001));
      expect(gold.changePercent, closeTo(1.0, 0.0001));

      final second = await repository.syncMarketData();
      expect(second.rowCount, 3);
      expect(await (await database.database).query('market_data_cache'), hasLength(3));
    });

    test('schema v6 exposes both market tables with provenance labels',
        () async {
      final database = await newDatabase();
      addTearDown(database.close);
      final tables = await (await database.database).rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).toList();
      expect(names, contains('fmp_market_context'));
      expect(names, contains('market_data_cache'));

      final columns = await (await database.database).rawQuery(
        'PRAGMA table_info(market_data_cache)',
      );
      expect(
        columns.map((column) => column['name']),
        containsAll(['provenance', 'source', 'kind', 'source_url']),
      );
    });
  });
}
