import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'wealth_dao.dart';
import 'wealth_database.dart';
import 'wealth_models.dart';
import 'week_identifier.dart';

const _uuidNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

class ImportSummary {
  const ImportSummary({
    required this.sourceId,
    required this.entityCount,
    required this.snapshotCount,
    required this.incomeStreamCount,
    required this.relationCount,
  });

  final String sourceId;
  final int entityCount;
  final int snapshotCount;
  final int incomeStreamCount;
  final int relationCount;
}

class WeeklyBundleImporter {
  WeeklyBundleImporter(this._database);

  final WealthDatabase _database;
  final _uuid = const Uuid();

  Future<ImportSummary> importBundle(String jsonText) async {
    final bundle = _parseBundle(jsonText);
    final db = await _database.database;
    final dao = WealthDao(_database);

    await db.transaction((transaction) async {
      await dao.upsertSource(bundle.source, executor: transaction);
      for (final entity in bundle.entities) {
        await dao.upsertEntity(entity.entity, executor: transaction);
      }

      for (final entity in bundle.entities) {
        for (final snapshot in entity.snapshots) {
          await dao.upsertSnapshot(snapshot, executor: transaction);
        }
        for (final stream in entity.incomeStreams) {
          await dao.upsertIncomeStream(stream, executor: transaction);
        }
        for (final relation in entity.relations) {
          if (await dao.getEntity(relation.toEntityId, executor: transaction) ==
              null) {
            throw FormatException(
              'Entity ${entity.entity.id} references missing target '
              '${relation.toEntityId}.',
            );
          }
          await dao.upsertRelation(relation, executor: transaction);
        }
      }
    });

    return ImportSummary(
      sourceId: bundle.source.id,
      entityCount: bundle.entities.length,
      snapshotCount: bundle.entities.fold(
        0,
        (sum, item) => sum + item.snapshots.length,
      ),
      incomeStreamCount: bundle.entities.fold(
        0,
        (sum, item) => sum + item.incomeStreams.length,
      ),
      relationCount: bundle.entities.fold(
        0,
        (sum, item) => sum + item.relations.length,
      ),
    );
  }

  _ParsedBundle _parseBundle(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Bundle root must be a JSON object.');
    }
    if (decoded['bundleVersion'] != '2.0') {
      throw FormatException(
        'Unsupported bundleVersion: ${decoded['bundleVersion']}. Expected 2.0.',
      );
    }
    final weekIdentifier = _requiredString(decoded, 'weekIdentifier');
    isoWeekMonday(weekIdentifier);
    final generatedAt = _parseTimestamp(decoded['generatedAt'], 'generatedAt');
    final sourceJson = _requiredObject(decoded, 'source');
    final sourceType = SourceTypeValue.parse(
      _requiredString(sourceJson, 'sourceType'),
    );
    if (sourceType != SourceType.jsonImport) {
      throw const FormatException(
        'Weekly bundles must use JSON_IMPORT sourceType.',
      );
    }
    final sourceTitle = _requiredString(sourceJson, 'title');
    final sourceUrl = _optionalString(sourceJson, 'url');
    if (sourceUrl != null) _validateUrl(sourceUrl, 'source.url');
    final sourceId = _uuid.v5(
      _uuidNamespace,
      '$weekIdentifier|$sourceTitle|${sourceUrl ?? ''}',
    );
    final source = WealthSource(
      id: sourceId,
      title: sourceTitle,
      url: sourceUrl,
      sourceType: sourceType,
      lastSyncedAt: generatedAt,
    );
    final entityRows = _requiredList(decoded, 'entities');
    final entityIds = <String>{};
    final entities = <_ParsedEntity>[];

    for (final rawEntity in entityRows) {
      if (rawEntity is! Map<String, dynamic>) {
        throw const FormatException('Each entity must be a JSON object.');
      }
      final entityId = _requiredString(rawEntity, 'id');
      if (!entityIds.add(entityId)) {
        throw FormatException('Duplicate entity ID in bundle: $entityId.');
      }
      final name = _requiredString(rawEntity, 'name');
      final metadataJson = _metadataJson(rawEntity);
      final entity = WealthEntity(
        id: entityId,
        category: EntityCategoryValue.parse(
          _requiredString(rawEntity, 'category'),
        ),
        name: name,
        subtitle: _optionalString(rawEntity, 'subtitle'),
        nationalityOrOrigin: _optionalString(rawEntity, 'nationalityOrOrigin'),
        metadataJson: metadataJson,
        sourceId: sourceId,
        createdAt: generatedAt,
        updatedAt: generatedAt,
      );
      final snapshots = _parseSnapshots(
        rawEntity,
        entityId: entityId,
        bundleWeek: weekIdentifier,
        generatedAt: generatedAt,
        sourceId: sourceId,
      );
      final incomeStreams = <IncomeStream>[];
      for (final rawStream in _optionalList(rawEntity, 'incomeStreams')) {
        if (rawStream is! Map<String, dynamic>) {
          throw const FormatException('Each income stream must be an object.');
        }
        final streamType = IncomeStreamTypeValue.parse(
          _requiredString(rawStream, 'streamType'),
        );
        final title = _requiredString(rawStream, 'title');
        final annualValue = _optionalNumber(rawStream, 'estimatedAnnualValue');
        final share = _optionalNumber(rawStream, 'portfolioSharePercent');
        if (share != null && (share < 0 || share > 100)) {
          throw FormatException(
            'portfolioSharePercent must be between 0 and 100 for $entityId.',
          );
        }
        final lastUpdatedWeek =
            _optionalString(rawStream, 'lastUpdatedWeek') ?? weekIdentifier;
        isoWeekMonday(lastUpdatedWeek);
        incomeStreams.add(
          IncomeStream(
            id: _uuid.v5(
              _uuidNamespace,
              'income|$entityId|${streamType.value}|$title',
            ),
            entityId: entityId,
            streamType: streamType,
            title: title,
            estimatedAnnualValue: annualValue,
            portfolioSharePercent: share,
            lastUpdatedWeek: lastUpdatedWeek,
          ),
        );
      }

      final relations = <EntityRelation>[];
      for (final rawRelation in _optionalList(rawEntity, 'relations')) {
        if (rawRelation is! Map<String, dynamic>) {
          throw const FormatException('Each relation must be an object.');
        }
        final targetId = _requiredString(rawRelation, 'targetId');
        if (targetId == entityId) {
          throw FormatException(
            'Entity $entityId cannot reference itself in a relation.',
          );
        }
        final relationType = EntityRelationTypeValue.parse(
          _requiredString(rawRelation, 'relationType'),
        );
        final detail = _optionalString(rawRelation, 'relationDetail');
        relations.add(
          EntityRelation(
            id: _uuid.v5(
              _uuidNamespace,
              'relation|$entityId|$targetId|${relationType.value}|${detail ?? ''}',
            ),
            fromEntityId: entityId,
            toEntityId: targetId,
            relationType: relationType,
            sourceId: sourceId,
            relationDetail: detail,
            validFrom: _optionalString(rawRelation, 'validFrom'),
            validTo: _optionalString(rawRelation, 'validTo'),
          ),
        );
      }
      entities.add(
        _ParsedEntity(
          entity: entity,
          snapshots: snapshots,
          incomeStreams: incomeStreams,
          relations: relations,
        ),
      );
    }

    return _ParsedBundle(source: source, entities: entities);
  }

  List<WeeklySnapshot> _parseSnapshots(
    Map<String, dynamic> rawEntity, {
    required String entityId,
    required String bundleWeek,
    required String generatedAt,
    required String sourceId,
  }) {
    final rawSnapshots = _optionalList(rawEntity, 'snapshots');
    final snapshotEntries = <Map<String, dynamic>>[];
    if (rawSnapshots.isNotEmpty) {
      if (rawEntity['snapshot'] != null) {
        throw FormatException(
          'Entity $entityId cannot define both snapshot and snapshots.',
        );
      }
      for (final rawSnapshot in rawSnapshots) {
        if (rawSnapshot is! Map<String, dynamic>) {
          throw const FormatException('Each snapshot must be a JSON object.');
        }
        snapshotEntries.add(rawSnapshot);
      }
    } else {
      final singleSnapshot = _optionalObject(rawEntity, 'snapshot');
      if (singleSnapshot != null) snapshotEntries.add(singleSnapshot);
    }

    final seenWeeks = <String>{};
    final snapshots = <WeeklySnapshot>[];
    for (final entry in snapshotEntries) {
      final week = _optionalString(entry, 'weekIdentifier') ?? bundleWeek;
      isoWeekMonday(week);
      if (!seenWeeks.add(week)) {
        throw FormatException(
          'Duplicate snapshot week $week for entity $entityId.',
        );
      }
      final currencyUnit = _optionalString(entry, 'currencyUnit') ?? 'USD_M';
      if (!const {'USD_M', 'USD_B'}.contains(currencyUnit)) {
        throw FormatException(
          'Unsupported currencyUnit $currencyUnit for $entityId. '
          'Use USD_M or USD_B.',
        );
      }
      snapshots.add(
        WeeklySnapshot(
          id: _uuid.v5(_uuidNamespace, 'snapshot|$entityId|$week'),
          entityId: entityId,
          weekIdentifier: week,
          recordedAt: entry['recordedAt'] == null
              ? generatedAt
              : _parseTimestamp(entry['recordedAt'], 'recordedAt'),
          totalNetWorth: _optionalNumber(entry, 'totalNetWorth'),
          currencyUnit: currencyUnit,
          summaryNote: _optionalString(entry, 'summaryNote'),
          sourceId: sourceId,
        ),
      );
    }
    return snapshots;
  }
}

class _ParsedBundle {
  const _ParsedBundle({required this.source, required this.entities});

  final WealthSource source;
  final List<_ParsedEntity> entities;
}

class _ParsedEntity {
  const _ParsedEntity({
    required this.entity,
    required this.snapshots,
    required this.incomeStreams,
    required this.relations,
  });

  final WealthEntity entity;
  final List<WeeklySnapshot> snapshots;
  final List<IncomeStream> incomeStreams;
  final List<EntityRelation> relations;
}

String _requiredString(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a string.');
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

Map<String, dynamic> _requiredObject(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$key must be a JSON object.');
  }
  return value;
}

Map<String, dynamic>? _optionalObject(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! Map<String, dynamic>) {
    throw FormatException('$key must be a JSON object.');
  }
  return value;
}

List<dynamic> _requiredList(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value is! List) throw FormatException('$key must be a JSON array.');
  return value;
}

List<dynamic> _optionalList(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value == null) return const [];
  if (value is! List) throw FormatException('$key must be a JSON array.');
  return value;
}

double? _optionalNumber(Map<String, dynamic> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw FormatException('$key must be a finite number.');
  }
  return value.toDouble();
}

String _parseTimestamp(Object? value, String field) {
  if (value is! String) {
    throw FormatException('$field must be an ISO timestamp.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$field must be an ISO timestamp.');
  return parsed.toUtc().toIso8601String();
}

String _metadataJson(Map<String, dynamic> entity) {
  final raw = entity['metadataJson'] ?? entity['metadata'];
  if (raw == null) return '{}';
  final decoded = raw is String ? jsonDecode(raw) : raw;
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('metadataJson must encode a JSON object.');
  }
  return jsonEncode(decoded);
}

void _validateUrl(String value, String field) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
      uri.host.isEmpty) {
    throw FormatException('$field must be a valid http or https URL.');
  }
}
