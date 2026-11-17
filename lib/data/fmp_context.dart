/// The kind of locally cached Financial Modeling Prep context row.
enum FmpContextKind {
  cpi('CPI'),
  indexQuote('INDEX_QUOTE');

  const FmpContextKind(this.dbValue);

  final String dbValue;

  static FmpContextKind parse(String value) => values.firstWhere(
    (kind) => kind.dbValue == value,
    orElse: () => throw FormatException('Unknown FMP context kind: $value'),
  );
}

/// A cached FMP data point shown alongside the IMF indicators.
class FmpContextRow {
  const FmpContextRow({
    required this.kind,
    required this.symbol,
    required this.label,
    required this.value,
    this.changePercent,
    required this.period,
    required this.sourceUrl,
    required this.fetchedAt,
  });

  final FmpContextKind kind;
  final String symbol;
  final String label;
  final double value;
  final double? changePercent;
  final String period;
  final String sourceUrl;
  final String fetchedAt;

  factory FmpContextRow.fromRow(Map<String, Object?> row) => FmpContextRow(
    kind: FmpContextKind.parse(row['kind']! as String),
    symbol: row['symbol']! as String,
    label: row['label']! as String,
    value: (row['value'] as num).toDouble(),
    changePercent: (row['change_percent'] as num?)?.toDouble(),
    period: row['period']! as String,
    sourceUrl: row['source_url']! as String,
    fetchedAt: row['fetched_at']! as String,
  );

  Map<String, Object?> toRow() => <String, Object?>{
    'kind': kind.dbValue,
    'symbol': symbol,
    'label': label,
    'value': value,
    'change_percent': changePercent,
    'period': period,
    'source_url': sourceUrl,
    'fetched_at': fetchedAt,
  };
}

/// Result of one explicit FMP context refresh.
class FmpSyncSummary {
  const FmpSyncSummary({
    required this.rowCount,
    required this.fetchedAt,
    this.errors = const <String>[],
  });

  final int rowCount;
  final String fetchedAt;
  final List<String> errors;
}
