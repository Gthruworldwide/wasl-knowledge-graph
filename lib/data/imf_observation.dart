import 'imf_sdmx_client.dart';

/// A locally cached CPI observation imported from the IMF SDMX API.
class ImfObservationRow {
  const ImfObservationRow({
    required this.id,
    required this.countryCode,
    required this.countryName,
    required this.seriesKey,
    required this.period,
    required this.value,
    required this.unit,
    required this.frequency,
    required this.sourceUrl,
    required this.fetchedAt,
  });

  final String id;
  final String countryCode;
  final String countryName;
  final String seriesKey;
  final String period;
  final double value;
  final String unit;
  final String frequency;
  final String sourceUrl;
  final String fetchedAt;

  factory ImfObservationRow.fromRow(Map<String, Object?> row) =>
      ImfObservationRow(
        id: row['id']! as String,
        countryCode: row['country_code']! as String,
        countryName: row['country_name']! as String,
        seriesKey: row['series_key']! as String,
        period: row['period']! as String,
        value: (row['value'] as num).toDouble(),
        unit: row['unit']! as String,
        frequency: row['frequency']! as String,
        sourceUrl: row['source_url']! as String,
        fetchedAt: row['fetched_at']! as String,
      );

  Map<String, Object?> toRow() => {
    'id': id,
    'country_code': countryCode,
    'country_name': countryName,
    'series_key': seriesKey,
    'period': period,
    'value': value,
    'unit': unit,
    'frequency': frequency,
    'source_url': sourceUrl,
    'fetched_at': fetchedAt,
  };
}

class ImfSettings {
  const ImfSettings({
    required this.countryCodes,
    required this.autoRefresh,
    required this.startYear,
    this.apiVersion = ImfApiVersion.v21,
    this.lastSyncAt,
  });

  final List<String> countryCodes;
  final bool autoRefresh;
  final int startYear;
  final ImfApiVersion apiVersion;
  final String? lastSyncAt;

  ImfSettings copyWith({
    List<String>? countryCodes,
    bool? autoRefresh,
    int? startYear,
    ImfApiVersion? apiVersion,
    String? lastSyncAt,
  }) =>
      ImfSettings(
        countryCodes: countryCodes ?? this.countryCodes,
        autoRefresh: autoRefresh ?? this.autoRefresh,
        startYear: startYear ?? this.startYear,
        apiVersion: apiVersion ?? this.apiVersion,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
}

class ImfImportSummary {
  const ImfImportSummary({
    required this.countryCount,
    required this.observationCount,
    required this.newsCount,
    required this.linkedEntityCount,
    required this.fetchedAt,
    required this.apiVersion,
  });

  final int countryCount;
  final int observationCount;
  final int newsCount;
  final int linkedEntityCount;
  final String fetchedAt;
  final ImfApiVersion apiVersion;
}
