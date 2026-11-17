import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for Yahoo Finance's public chart endpoint. No API key is needed,
/// so request URLs are safe to persist as source provenance.
const String yahooChartBaseUrl =
    'https://query1.finance.yahoo.com/v8/finance/chart';

/// Gold and silver market assets fetched explicitly from Yahoo Finance.
///
/// `XAUUSD=X` is intentionally excluded: it is not returned by this endpoint.
/// `GC=F` is the front-month COMEX gold future; `GLD` and `SLV` are the
/// gold and silver ETFs used as cross-checks.
enum MarketAssetKind {
  goldFuture(
    symbol: 'GC=F',
    labelEn: 'Gold futures',
    labelAr: 'العقود الآجلة للذهب',
    dbValue: 'GOLD_FUTURE',
  ),
  goldEtf(
    symbol: 'GLD',
    labelEn: 'Gold ETF (GLD)',
    labelAr: 'صندوق الذهب (GLD)',
    dbValue: 'GOLD_ETF',
  ),
  silverEtf(
    symbol: 'SLV',
    labelEn: 'Silver ETF (SLV)',
    labelAr: 'صندوق الفضة (SLV)',
    dbValue: 'SILVER_ETF',
  );

  const MarketAssetKind({
    required this.symbol,
    required this.labelEn,
    required this.labelAr,
    required this.dbValue,
  });

  final String symbol;
  final String labelEn;
  final String labelAr;
  final String dbValue;

  String label(bool isArabic) => isArabic ? labelAr : labelEn;

  static MarketAssetKind parse(String value) => values.firstWhere(
    (kind) => kind.dbValue == value,
    orElse: () => throw FormatException('Unknown market asset kind: $value'),
  );
}

/// One quote parsed from a Yahoo chart response.
class MarketQuote {
  const MarketQuote({
    required this.symbol,
    required this.price,
    this.name,
    this.changePercent,
    this.period,
  });

  final String symbol;
  final double price;
  final String? name;
  final double? changePercent;
  final String? period;
}

class MarketDataApiException implements Exception {
  const MarketDataApiException(this.statusCode, this.uri, this.message);

  final int statusCode;
  final Uri uri;
  final String message;

  @override
  String toString() => 'Market data request failed ($statusCode): $message';
}

/// Minimal, key-free client for Yahoo Finance chart quotes.
///
/// Every request URL is retrievable as provenance and contains no credentials.
class MarketDataClient {
  MarketDataClient({
    http.Client? client,
    this.baseUrl = yahooChartBaseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  Uri chartUri(String symbol) => Uri.parse(
    '${baseUrl.trimRight()}/$symbol'
    '?interval=1d&range=5d',
  );

  Future<MarketQuote?> fetchQuote(MarketAssetKind asset) async {
    final uri = chartUri(asset.symbol);
    final response = await _client.get(uri).timeout(timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (response.statusCode != 200) {
      throw MarketDataApiException(
        response.statusCode,
        uri,
        body.isEmpty ? 'HTTP ${response.statusCode}' : _preview(body),
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw FormatException('Market data returned non-JSON: ${_preview(body)}');
    }
    final meta = _meta(decoded);
    if (meta == null) return null;
    final rawPrice = meta['regularMarketPrice'];
    final price = rawPrice is num ? rawPrice.toDouble() : null;
    if (price == null || price.isNaN || price.isInfinite || price <= 0) {
      return null;
    }
    final previous = _optionalDouble(
      meta['chartPreviousClose'] ?? meta['previousClose'],
    );
    final changePercent =
        previous != null && previous > 0 ? (price / previous - 1) * 100 : null;
    final rawTime = meta['regularMarketTime'];
    String? period;
    if (rawTime is num) {
      period = DateTime.fromMillisecondsSinceEpoch(
        rawTime.toInt() * 1000,
        isUtc: true,
      ).toIso8601String();
    }
    return MarketQuote(
      symbol: '${meta['symbol'] ?? asset.symbol}',
      name: meta['shortName'] is String
          ? meta['shortName'] as String
          : meta['longName'] is String
          ? meta['longName'] as String
          : null,
      price: price,
      changePercent: changePercent,
      period: period,
    );
  }

  Map<String, dynamic>? _meta(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final chart = decoded['chart'];
    if (chart is! Map<String, dynamic>) return null;
    final result = chart['result'];
    if (result is! List || result.isEmpty) return null;
    final first = result.first;
    if (first is! Map<String, dynamic>) return null;
    final meta = first['meta'];
    return meta is Map<String, dynamic> ? meta : null;
  }

  double? _optionalDouble(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isNaN || number.isInfinite ? null : number;
  }

  String _preview(Object? value) {
    final text = value?.toString() ?? '';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}
