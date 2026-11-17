import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'fmp_client.dart';
import 'fmp_context.dart';
import 'imf_cpi_catalog.dart';
import 'imf_observation.dart';
import 'imf_sdmx_client.dart';
import 'wealth_dao.dart';
import 'wealth_database.dart';
import 'wealth_models.dart';
import 'week_identifier.dart';

const String _imfPreferencesPrefix = 'wasl.imf.cpi';
const String _fmpPreferencesPrefix = 'wasl.fmp';
const String _uuidNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';
const Duration _autoRefreshInterval = Duration(hours: 24);

/// Orchestrates IMF CPI imports: fetch -> local cache -> wealth graph notes.
class ImfRepository {
  ImfRepository(
    this._database, {
    ImfSdmxClient? client,
    FmpClient? fmpClient,
    this.preferences,
  })  : _client = client ?? ImfSdmxClient(),
        _fmpClient = fmpClient ?? FmpClient();

  final WealthDatabase _database;
  final ImfSdmxClient _client;
  final FmpClient _fmpClient;
  final SharedPreferences? preferences;
  static const _uuid = Uuid();

  Future<SharedPreferences> get _prefs async =>
      preferences ?? await SharedPreferences.getInstance();

  Future<ImfSettings> loadSettings() async {
    final prefs = await _prefs;
    final codes = prefs.getStringList('$_imfPreferencesPrefix.countries');
    final versionLabel = prefs.getString('$_imfPreferencesPrefix.apiVersion');
    ImfApiVersion apiVersion;
    try {
      apiVersion = ImfApiVersion.parse(versionLabel ?? ImfApiVersion.v21.label);
    } on FormatException {
      apiVersion = ImfApiVersion.v21;
    }
    return ImfSettings(
      countryCodes: codes == null || codes.isEmpty
          ? List<String>.of(defaultImfCountryCodes)
          : codes,
      autoRefresh: prefs.getBool('$_imfPreferencesPrefix.autoRefresh') ?? false,
      startYear: prefs.getInt('$_imfPreferencesPrefix.startYear') ?? 2022,
      apiVersion: apiVersion,
      lastSyncAt: prefs.getString('$_imfPreferencesPrefix.lastSyncAt'),
    );
  }

  Future<void> saveSettings(ImfSettings settings) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      '$_imfPreferencesPrefix.countries',
      settings.countryCodes,
    );
    await prefs.setBool(
      '$_imfPreferencesPrefix.autoRefresh',
      settings.autoRefresh,
    );
    await prefs.setInt('$_imfPreferencesPrefix.startYear', settings.startYear);
    await prefs.setString(
      '$_imfPreferencesPrefix.apiVersion',
      settings.apiVersion.label,
    );
    if (settings.lastSyncAt != null) {
      await prefs.setString(
        '$_imfPreferencesPrefix.lastSyncAt',
        settings.lastSyncAt!,
      );
    }
  }

  /// True when auto-refresh is enabled and the last successful import is old.
  Future<bool> shouldAutoRefresh([DateTime? now]) async {
    final settings = await loadSettings();
    if (!settings.autoRefresh || settings.lastSyncAt == null) return false;
    final lastSync = DateTime.tryParse(settings.lastSyncAt!);
    if (lastSync == null) return true;
    return (now ?? DateTime.now()).toUtc().difference(lastSync.toUtc()) >
        _autoRefreshInterval;
  }

  // --- Financial Modeling Prep context -----------------------------------

  /// Returns the runtime-entered FMP key. It is never logged or embedded.
  Future<String> loadFmpApiKey() async =>
      (await _prefs).getString('$_fmpPreferencesPrefix.apiKey') ?? '';

  Future<bool> hasFmpApiKey() async =>
      (await loadFmpApiKey()).trim().isNotEmpty;

  Future<void> saveFmpApiKey(String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Enter an FMP API key before saving.');
    }
    await (await _prefs).setString('$_fmpPreferencesPrefix.apiKey', trimmed);
  }

  Future<void> clearFmpApiKey() async {
    await (await _prefs).remove('$_fmpPreferencesPrefix.apiKey');
  }

  /// Explicitly fetches FMP CPI and major index quotes into the local cache.
  ///
  /// Key material is sent only as a request header; saved [sourceUrl] values
  /// contain no credentials. A missing quote does not discard other results.
  Future<FmpSyncSummary> syncFmpContext({bool isArabic = false}) async {
    final apiKey = await loadFmpApiKey();
    if (apiKey.trim().isEmpty) {
      throw StateError(
        isArabic
            ? 'أضف مفتاح FMP من الإعدادات أولاً.'
            : 'Add an FMP API key in settings first.',
      );
    }
    final client = _fmpClient.withApiKey(apiKey);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final errors = <String>[];
    final rows = <FmpContextRow>[];

    try {
      final points = await client.fetchEconomicIndicator('CPI');
      if (points.isEmpty) {
        errors.add('FMP returned no CPI observations.');
      } else {
        points.sort((a, b) => b.date.compareTo(a.date));
        final latest = points.first;
        rows.add(FmpContextRow(
          kind: FmpContextKind.cpi,
          symbol: 'CPI',
          label: latest.name,
          value: latest.value,
          period: latest.date,
          sourceUrl: client.economicIndicatorsUri(name: 'CPI').toString(),
          fetchedAt: fetchedAt,
        ));
      }
    } on Object catch (error) {
      errors.add('FMP CPI: $error');
    }

    // The free key supports only single-symbol /stable/quote calls. Each
    // symbol is fetched individually; batch/economic-calendar/treasury
    // endpoints are documented as unavailable in WASL_API_COVERAGE.md.
    for (final symbol in fmpAllQuoteSymbols) {
      try {
        final quote = await client.fetchQuote(symbol);
        if (quote == null) {
          errors.add('FMP returned no quote for $symbol.');
          continue;
        }
        rows.add(FmpContextRow(
          kind: fmpKindForSymbol(symbol),
          symbol: quote.symbol,
          label: quote.name,
          value: quote.price,
          changePercent: quote.changePercentage,
          period: _fmpQuotePeriod(quote.timestamp),
          sourceUrl: client.quoteUri(symbol: symbol).toString(),
          fetchedAt: fetchedAt,
        ));
      } on Object catch (error) {
        errors.add('FMP $symbol: $error');
      }
    }

    if (rows.isEmpty) {
      throw StateError(
        errors.isEmpty
            ? (isArabic
                ? 'لم يتم جلب أي بيانات من FMP.'
                : 'No FMP context could be fetched.')
            : errors.join(' '),
      );
    }

    final db = await _database.database;
    await db.transaction((transaction) async {
      for (final row in rows) {
        await transaction.insert(
          'fmp_market_context',
          row.toRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    return FmpSyncSummary(
      rowCount: rows.length,
      fetchedAt: fetchedAt,
      errors: errors,
    );
  }

  /// Latest cached FMP rows, one per symbol for the requested [kind].
  Future<List<FmpContextRow>> fmpContext({FmpContextKind? kind}) async {
    final db = await _database.database;
    final rows = await db.query(
      'fmp_market_context',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : <Object?>[kind.dbValue],
      orderBy: 'fetched_at DESC',
    );
    final seen = <String>{};
    return rows
        .map(FmpContextRow.fromRow)
        .where((row) => seen.add('${row.kind.dbValue}:${row.symbol}'))
        .toList();
  }

  String _fmpQuotePeriod(int? timestamp) {
    if (timestamp == null) return 'unknown';
    return DateTime.fromMillisecondsSinceEpoch(
      timestamp * 1000,
      isUtc: true,
    ).toIso8601String();
  }

  Future<ImfImportSummary> importCpi({
    List<String>? countryCodes,
    int? startYear,
    ImfApiVersion? apiVersion,
    bool isArabic = false,
  }) async {
    final settings = await loadSettings();
    final codes = countryCodes ?? settings.countryCodes;
    if (codes.isEmpty) {
      throw ArgumentError('Select at least one country to import.');
    }
    final year = startYear ?? settings.startYear;
    final version = apiVersion ?? settings.apiVersion;
    final client = _client.forVersion(version);
    final flowRef = ImfCpiCatalog.flowRefFor(version);
    final key = ImfCpiCatalog.keyFor(codes);

    // Record the exact URL used for this request as the source provenance.
    final requestUri = client.dataUri(
      flowRef: flowRef,
      key: key,
      providerRef: ImfCpiCatalog.providerRef,
      startPeriod: '$year',
      dimensionAtObservation: 'TIME_PERIOD',
      detail: 'dataonly',
      includeHistory: false,
    );
    final message = await client.fetchData(
      flowRef: flowRef,
      key: key,
      providerRef: ImfCpiCatalog.providerRef,
      startPeriod: '$year',
      dimensionAtObservation: 'TIME_PERIOD',
      detail: 'dataonly',
      includeHistory: false,
    );
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final sourceUrl = requestUri.toString();
    final sourceId = _uuid.v5(_uuidNamespace, 'IMF-SDMX-CPI');
    final dao = WealthDao(_database);
    final requestedCodes = codes.map((code) => code.toUpperCase()).toSet();
    final countryIds = <String>{};
    var observationCount = 0;
    var linkedEntityCount = 0;

    final db = await _database.database;
    await db.transaction((transaction) async {
      await dao.upsertSource(
        WealthSource(
          id: sourceId,
          title: 'IMF Consumer Price Index (SDMX ${version.label})',
          url: sourceUrl,
          sourceType: SourceType.rssFeed,
          lastSyncedAt: fetchedAt,
        ),
        executor: transaction,
      );

      final related = <String, List<EntityRelation>>{};
      for (final series in message.series) {
        final countryCode = series.code('COUNTRY').toUpperCase();
        if (!requestedCodes.contains(countryCode)) continue;
        final countryName = series.name('COUNTRY');
        final country = imfCountry(countryCode);
        final displayName = country?.name ?? countryName;
        final seriesKey = series.key;
        if (series.observations.isEmpty) continue;
        countryIds.add(countryCode);

        final newsId = _uuid.v5(
          _uuidNamespace,
          'IMF-CPI-NEWS|$countryCode',
        );
        final now = fetchedAt;
        await dao.upsertEntity(
          WealthEntity(
            id: newsId,
            category: EntityCategory.economicNews,
            name: isArabic
                ? '${country?.arabicName ?? countryName}: التضخم السنوي'
                : '$displayName: annual CPI inflation',
            subtitle: isArabic
                ? 'مؤشر IMF CPI • كل السلع • شهري'
                : 'IMF CPI • All items • Monthly',
            metadataJson: jsonEncode(<String, Object?>{
              'countryCode': countryCode,
              'indicator': 'CPI_YOY_PERCENT',
              'provider': 'IMF',
              'apiVersion': version.label,
              'flowRef': flowRef,
              'seriesKey': seriesKey,
              'sourceUrl': sourceUrl,
            }),
            sourceId: sourceId,
            createdAt: now,
            updatedAt: now,
          ),
          executor: transaction,
        );

        for (final observation in series.observations) {
          final week = _weekIdentifierForPeriod(observation.period);
          final valueLabel = observation.value.toStringAsFixed(2);
          final note = isArabic
              ? 'مؤشر IMF CPI: $valueLabel٪ تغيّر سنوي (كل السلع، $displayName) '
                  'في ${observation.period}.'
              : 'IMF CPI: $valueLabel% YoY (all items, $displayName) '
                  'in ${observation.period}.';
          await dao.upsertSnapshot(
            WeeklySnapshot(
              id: _uuid.v5(
                _uuidNamespace,
                'IMF-CPI-OBS|$countryCode|$seriesKey|${observation.period}',
              ),
              entityId: newsId,
              weekIdentifier: week,
              recordedAt: fetchedAt,
              summaryNote: note,
              currencyUnit: ImfCpiCatalog.unit,
              sourceId: sourceId,
            ),
            executor: transaction,
          );
          await transaction.insert(
            'imf_observations',
            ImfObservationRow(
              id: _uuid.v5(
                _uuidNamespace,
                'IMF-CPI-ROW|$countryCode|$seriesKey|${observation.period}',
              ),
              countryCode: countryCode,
              countryName: displayName,
              seriesKey: seriesKey,
              period: observation.period,
              value: observation.value,
              unit: ImfCpiCatalog.unit,
              frequency: ImfCpiCatalog.frequency,
              sourceUrl: sourceUrl,
              fetchedAt: fetchedAt,
            ).toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          observationCount++;
        }

        final matches = await _matchingEntities(transaction, country);
        related[countryCode] = matches.map(
          (entity) => EntityRelation(
            id: _uuid.v5(
              _uuidNamespace,
              'IMF-CPI-REL|${entity.id}|$countryCode',
            ),
            fromEntityId: entity.id,
            toEntityId: newsId,
            relationType: EntityRelationType.impactedByNews,
            relationDetail: 'IMF CPI • $displayName • All items',
            sourceId: sourceId,
          ),
        ).toList();
      }

      for (final relations in related.values) {
        for (final relation in relations) {
          await dao.upsertRelation(relation, executor: transaction);
          linkedEntityCount++;
        }
      }
    });

    if (countryIds.isEmpty) {
      throw StateError(
        'The IMF CPI query returned no observations for the selected '
        'countries.',
      );
    }
    await saveSettings(settings.copyWith(
      countryCodes: codes,
      startYear: year,
      apiVersion: version,
      lastSyncAt: fetchedAt,
    ));
    return ImfImportSummary(
      countryCount: countryIds.length,
      observationCount: observationCount,
      newsCount: countryIds.length,
      linkedEntityCount: linkedEntityCount,
      fetchedAt: fetchedAt,
      apiVersion: version,
    );
  }

  Future<List<ImfObservationRow>> latestObservations() async {
    final db = await _database.database;
    final rows = await db.query('imf_observations');
    final observations = rows.map(ImfObservationRow.fromRow).toList();
    final byCountry = <String, ImfObservationRow>{};
    for (final observation in observations) {
      final current = byCountry[observation.countryCode];
      if (current == null || observation.period.compareTo(current.period) > 0) {
        byCountry[observation.countryCode] = observation;
      }
    }
    final latest = byCountry.values.toList()
      ..sort((a, b) => a.countryName.compareTo(b.countryName));
    return latest;
  }

  Future<List<ImfObservationRow>> historyFor(
    String countryCode, {
    int limit = 24,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'imf_observations',
      where: 'country_code = ?',
      whereArgs: [countryCode.toUpperCase()],
      orderBy: 'period DESC',
      limit: limit,
    );
    return rows
        .map(ImfObservationRow.fromRow)
        .toList()
        .reversed
        .toList();
  }

  Future<List<String>> savedCountryCodes() async =>
      (await loadSettings()).countryCodes;

  Future<WealthEntity?> newsEntityFor(String countryCode) async {
    final dao = WealthDao(_database);
    final entities = await dao.searchEntities('');
    for (final entity in entities) {
      if (entity.category != EntityCategory.economicNews) continue;
      if (entity.metadataJson.contains('"countryCode":"${countryCode.toUpperCase()}"')) {
        return entity;
      }
    }
    return null;
  }

  Future<List<WealthEntity>> _matchingEntities(
    DatabaseExecutor executor,
    ImfCountry? country,
  ) async {
    if (country == null) return const <WealthEntity>[];
    final rows = await executor.query('entities');
    final entities = rows.map(WealthEntity.fromRow).toList();
    return entities.where((entity) {
      if (entity.category == EntityCategory.economicNews) return false;
      final candidates = <String>{
        if (entity.nationalityOrOrigin != null) entity.nationalityOrOrigin!,
        ..._metadataStrings(entity.metadataJson),
      };
      for (final candidate in candidates) {
        final normalized = candidate.toLowerCase().trim();
        if (normalized.isEmpty) continue;
        if (normalized == country.code.toLowerCase() ||
            normalized == country.name.toLowerCase() ||
            normalized == country.arabicName ||
            country.name.toLowerCase().contains(normalized) ||
            normalized.contains(country.name.toLowerCase())) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  List<String> _metadataStrings(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return const <String>[];
      return decoded.values
          .whereType<String>()
          .map((value) => value.trim())
          .toList();
    } on Object {
      return const <String>[];
    }
  }

  String _weekIdentifierForPeriod(String period) {
    final match = RegExp(r'^(\d{4})(?:-M(\d{1,2})|-Q(\d))?$')
        .firstMatch(period.trim());
    if (match == null) return currentIsoWeekIdentifier();
    final year = int.parse(match.group(1)!);
    final month = match.group(2) != null
        ? int.parse(match.group(2)!)
        : match.group(3) != null
        ? int.parse(match.group(3)!) * 3 - 2
        : 1;
    return currentIsoWeekIdentifier(DateTime.utc(year, month, 1));
  }
}
