import 'package:sqflite/sqflite.dart';

import 'market_data_client.dart';
import 'wealth_database.dart';

/// A locally cached market-data row. [provenance] is always one of
/// `live`, `cached`, `synthetic`, `manual`; rows written here are `cached`
/// results of an explicit `live` fetch. Synthetic data is never produced here.
class MarketDataRow {
  const MarketDataRow({
    required this.source,
    required this.asset,
    required this.symbol,
    required this.label,
    required this.value,
    this.changePercent,
    required this.period,
    required this.sourceUrl,
    required this.fetchedAt,
    required this.provenance,
  });

  final String source;
  final MarketAssetKind asset;
  final String symbol;
  final String label;
  final double value;
  final double? changePercent;
  final String period;
  final String sourceUrl;
  final String fetchedAt;
  final String provenance;

  factory MarketDataRow.fromRow(Map<String, Object?> row) => MarketDataRow(
    source: row['source']! as String,
    asset: MarketAssetKind.parse(row['kind']! as String),
    symbol: row['symbol']! as String,
    label: row['label']! as String,
    value: (row['value'] as num).toDouble(),
    changePercent: (row['change_percent'] as num?)?.toDouble(),
    period: row['period']! as String,
    sourceUrl: row['source_url']! as String,
    fetchedAt: row['fetched_at']! as String,
    provenance: row['provenance']! as String,
  );

  Map<String, Object?> toRow() => <String, Object?>{
    'source': source,
    'kind': asset.dbValue,
    'symbol': symbol,
    'label': label,
    'value': value,
    'change_percent': changePercent,
    'period': period,
    'source_url': sourceUrl,
    'fetched_at': fetchedAt,
    'provenance': provenance,
  };
}

class MarketSyncSummary {
  const MarketSyncSummary({
    required this.rowCount,
    required this.fetchedAt,
    this.errors = const <String>[],
  });

  final int rowCount;
  final String fetchedAt;
  final List<String> errors;
}

/// Explicit, key-free fetch and local cache of Yahoo gold/silver quotes.
class MarketDataRepository {
  MarketDataRepository(this._database, {MarketDataClient? client})
    : _client = client ?? MarketDataClient();

  final WealthDatabase _database;
  final MarketDataClient _client;

  static const String sourceName = 'YAHOO';

  /// Fetches every configured asset one at a time. A missing quote does not
  /// discard the others; failures are returned as warnings.
  Future<MarketSyncSummary> syncMarketData({bool isArabic = false}) async {
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final errors = <String>[];
    final rows = <MarketDataRow>[];

    for (final asset in MarketAssetKind.values) {
      try {
        final quote = await _client.fetchQuote(asset);
        if (quote == null) {
          errors.add('No quote returned for ${asset.symbol}.');
          continue;
        }
        rows.add(
          MarketDataRow(
            source: sourceName,
            asset: asset,
            symbol: quote.symbol,
            label: quote.name ?? asset.labelEn,
            value: quote.price,
            changePercent: quote.changePercent,
            period: quote.period ?? 'unknown',
            sourceUrl: _client.chartUri(asset.symbol).toString(),
            fetchedAt: fetchedAt,
            provenance: 'cached',
          ),
        );
      } on Object catch (error) {
        errors.add('${asset.symbol}: $error');
      }
    }

    if (rows.isEmpty) {
      throw StateError(
        errors.isEmpty
            ? (isArabic
                ? 'لم يتم جلب أي بيانات سوق.'
                : 'No market data could be fetched.')
            : errors.join(' '),
      );
    }

    final db = await _database.database;
    await db.transaction((transaction) async {
      for (final row in rows) {
        await transaction.insert(
          'market_data_cache',
          row.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return MarketSyncSummary(
      rowCount: rows.length,
      fetchedAt: fetchedAt,
      errors: errors,
    );
  }

  /// Latest cached row per asset, newest first.
  Future<List<MarketDataRow>> latest({MarketAssetKind? asset}) async {
    final db = await _database.database;
    final rows = await db.query(
      'market_data_cache',
      where: asset == null ? null : 'kind = ?',
      whereArgs: asset == null ? null : <Object?>[asset.dbValue],
      orderBy: 'fetched_at DESC',
    );
    final seen = <String>{};
    return rows
        .map(MarketDataRow.fromRow)
        .where((row) => seen.add(row.asset.dbValue))
        .toList();
  }
}
