import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the stable Financial Modeling Prep REST API.
const String fmpStableBaseUrl = 'https://financialmodelingprep.com/stable';

/// One row returned by FMP's `/stable/economic-indicators` endpoint.
class FmpIndicatorPoint {
  const FmpIndicatorPoint({
    required this.name,
    required this.date,
    required this.value,
  });

  final String name;
  final String date;
  final double value;
}

/// One row returned by FMP's `/stable/quote` endpoint.
class FmpQuote {
  const FmpQuote({
    required this.symbol,
    required this.name,
    required this.price,
    this.change,
    this.changePercentage,
    this.timestamp,
  });

  final String symbol;
  final String name;
  final double price;
  final double? change;
  final double? changePercentage;
  final int? timestamp;
}

class FmpApiException implements Exception {
  const FmpApiException(this.statusCode, this.uri, this.message);

  final int statusCode;
  final Uri uri;
  final String message;

  @override
  String toString() => 'FMP API request failed ($statusCode): $message';
}

/// Minimal client for the FMP endpoints used by the indicators screen.
///
/// The API key is supplied at runtime and sent in an `apikey` **header**, never
/// in the query string. Request URLs are therefore safe to persist as source
/// provenance, and [FmpApiException] messages are scrubbed of the key.
class FmpClient {
  FmpClient({
    http.Client? client,
    this.apiKey = '',
    this.baseUrl = fmpStableBaseUrl,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String apiKey;
  final String baseUrl;
  final Duration timeout;

  /// Returns a client using another key while reusing the same HTTP client.
  FmpClient withApiKey(String key) => key == apiKey
      ? this
      : FmpClient(
          client: _client,
          apiKey: key,
          baseUrl: baseUrl,
          timeout: timeout,
        );

  Uri economicIndicatorsUri({required String name}) =>
      _uri('economic-indicators', <String, String>{'name': name});

  Uri quoteUri({required String symbol}) =>
      _uri('quote', <String, String>{'symbol': symbol});

  Future<List<FmpIndicatorPoint>> fetchEconomicIndicator(String name) async {
    _requireKey();
    final decoded = await _getJson(economicIndicatorsUri(name: name));
    if (decoded is! List) {
      throw FormatException(
        _safe(
          'FMP economic-indicators must return a JSON array: '
          '${_preview(decoded)}',
        ),
      );
    }
    final points = <FmpIndicatorPoint>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final rawValue = item['value'];
      final value = rawValue is num ? rawValue.toDouble() : null;
      final rawDate = item['date'];
      if (value == null || value.isNaN || value.isInfinite || rawDate == null) {
        continue;
      }
      points.add(FmpIndicatorPoint(
        name: '${item['name'] ?? name}',
        date: '$rawDate',
        value: value,
      ));
    }
    return points;
  }

  Future<FmpQuote?> fetchQuote(String symbol) async {
    _requireKey();
    final decoded = await _getJson(quoteUri(symbol: symbol));
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map<String, dynamic>) return null;
    final rawPrice = first['price'];
    final price = rawPrice is num ? rawPrice.toDouble() : null;
    if (price == null || price.isNaN || price.isInfinite) return null;
    return FmpQuote(
      symbol: '${first['symbol'] ?? symbol}',
      name: '${first['name'] ?? symbol}',
      price: price,
      change: _optionalDouble(first['change']),
      changePercentage: _optionalDouble(first['changePercentage']),
      timestamp: (first['timestamp'] as num?)?.toInt(),
    );
  }

  Uri _uri(String path, Map<String, String> query) {
    final encoded = query.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
    return Uri.parse('${baseUrl.trimRight()}/$path?$encoded');
  }

  Future<Object?> _getJson(Uri uri) async {
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(timeout);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (response.statusCode != 200) {
      throw FmpApiException(
        response.statusCode,
        uri,
        _safe(body.isEmpty ? 'HTTP ${response.statusCode}' : body),
      );
    }
    try {
      return jsonDecode(body);
    } on FormatException {
      throw FormatException(_safe('FMP returned non-JSON data: ${_preview(body)}'));
    }
  }

  Map<String, String> get _headers => <String, String>{
    'Accept': 'application/json',
    if (apiKey.isNotEmpty) 'apikey': apiKey,
  };

  void _requireKey() {
    if (apiKey.trim().isEmpty) {
      throw ArgumentError('An FMP API key is required. Add it in app settings.');
    }
  }

  /// Defensive scrubbing in case an upstream error echoes request headers.
  String _safe(String message) => apiKey.isEmpty
      ? message
      : message.replaceAll(apiKey, '[REDACTED]');

  String _preview(Object? value) {
    final text = value?.toString() ?? '';
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  double? _optionalDouble(Object? value) {
    if (value is! num) return null;
    final number = value.toDouble();
    return number.isNaN || number.isInfinite ? null : number;
  }
}
