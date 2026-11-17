import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'wealth_dao.dart';
import 'wealth_database.dart';
import 'wealth_models.dart';
import 'week_identifier.dart';

/// User-provided values for creating or editing an entity without JSON.
class EntityDraft {
  const EntityDraft({
    required this.category,
    required this.name,
    this.subtitle,
    this.nationalityOrOrigin,
    this.sourceTitle,
    this.sourceUrl,
    this.incomeStreams = const [],
    this.links = const [],
  });

  final EntityCategory category;
  final String name;
  final String? subtitle;
  final String? nationalityOrOrigin;
  final String? sourceTitle;
  final String? sourceUrl;
  final List<IncomeStreamDraft> incomeStreams;
  final List<EntityLinkDraft> links;
}

class IncomeStreamDraft {
  const IncomeStreamDraft({
    this.id,
    required this.streamType,
    required this.title,
    this.estimatedAnnualValue,
    this.portfolioSharePercent,
  });

  /// Existing stream ID when editing; null when the stream is new.
  final String? id;
  final IncomeStreamType streamType;
  final String title;
  final double? estimatedAnnualValue;
  final double? portfolioSharePercent;
}

class EntityLinkDraft {
  const EntityLinkDraft({
    this.id,
    required this.targetId,
    required this.relationType,
    this.relationDetail,
  });

  /// Existing relation ID when editing; null when the link is new.
  final String? id;
  final String targetId;
  final EntityRelationType relationType;
  final String? relationDetail;
}

class WealthMutations {
  WealthMutations(WealthDatabase database)
    : _database = database,
      _dao = WealthDao(database);

  final WealthDatabase _database;
  final WealthDao _dao;
  static const _uuid = Uuid();

  Future<WealthEntity> createEntity(EntityDraft draft) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final week = currentIsoWeekIdentifier();
    final sourceId = _uuid.v4();
    final entityId = _uuid.v4();
    final entity = WealthEntity(
      id: entityId,
      category: draft.category,
      name: draft.name,
      subtitle: draft.subtitle,
      nationalityOrOrigin: draft.nationalityOrOrigin,
      sourceId: sourceId,
      createdAt: now,
      updatedAt: now,
    );
    final db = await _database.database;
    await db.transaction((transaction) async {
      await _dao.upsertSource(
        WealthSource(
          id: sourceId,
          title: draft.sourceTitle ?? 'Manual entry',
          url: draft.sourceUrl,
          sourceType: SourceType.manual,
          lastSyncedAt: now,
        ),
        executor: transaction,
      );
      await _dao.upsertEntity(entity, executor: transaction);
      for (final stream in draft.incomeStreams) {
        await _dao.upsertIncomeStream(
          IncomeStream(
            id: stream.id ?? _uuid.v4(),
            entityId: entityId,
            streamType: stream.streamType,
            title: stream.title,
            estimatedAnnualValue: stream.estimatedAnnualValue,
            portfolioSharePercent: stream.portfolioSharePercent,
            lastUpdatedWeek: week,
          ),
          executor: transaction,
        );
      }
      await _validateLinks(draft.links, entityId, transaction);
      for (final link in draft.links) {
        await _dao.upsertRelation(
          EntityRelation(
            id: link.id ?? _uuid.v4(),
            fromEntityId: entityId,
            toEntityId: link.targetId,
            relationType: link.relationType,
            relationDetail: link.relationDetail,
            sourceId: sourceId,
          ),
          executor: transaction,
        );
      }
    });
    return entity;
  }

  /// Adds one weekly snapshot without touching earlier history.
  Future<WeeklySnapshot> addSnapshot({
    required WealthEntity entity,
    required String weekIdentifier,
    required String currencyUnit,
    double? totalNetWorth,
    String? summaryNote,
  }) async {
    isoWeekMonday(weekIdentifier);
    if (!const {'USD_M', 'USD_B'}.contains(currencyUnit)) {
      throw const FormatException('Currency unit must be USD_M or USD_B.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await _database.database;
    late WeeklySnapshot snapshot;
    await db.transaction((transaction) async {
      final existing = await transaction.query(
        'weekly_snapshots',
        columns: ['id'],
        where: 'entity_id = ? AND week_identifier = ?',
        whereArgs: [entity.id, weekIdentifier],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw FormatException(
          'A weekly snapshot for $weekIdentifier already exists for '
          '${entity.name}.',
        );
      }
      var sourceId = entity.sourceId;
      if (sourceId == null) {
        sourceId = _uuid.v4();
        await _dao.upsertSource(
          WealthSource(
            id: sourceId,
            title: 'Manual weekly update',
            sourceType: SourceType.manual,
            lastSyncedAt: now,
          ),
          executor: transaction,
        );
      }
      snapshot = WeeklySnapshot(
        id: _uuid.v4(),
        entityId: entity.id,
        weekIdentifier: weekIdentifier,
        recordedAt: now,
        totalNetWorth: totalNetWorth,
        currencyUnit: currencyUnit,
        summaryNote: summaryNote,
        sourceId: sourceId,
      );
      await _dao.upsertSnapshot(snapshot, executor: transaction);
    });
    return snapshot;
  }

  Future<void> updateEntity({
    required WealthEntity entity,
    required EntityDraft draft,
    required List<IncomeStream> previousStreams,
    required List<EntityRelation> previousLinks,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final week = currentIsoWeekIdentifier();
    final existingStreamWeeks = {
      for (final stream in previousStreams) stream.id: stream.lastUpdatedWeek,
    };
    final existingLinkSources = {
      for (final link in previousLinks) link.id: link.sourceId,
    };
    final db = await _database.database;
    await db.transaction((transaction) async {
      var sourceId = entity.sourceId;
      if (sourceId == null) {
        sourceId = _uuid.v4();
        await _dao.upsertSource(
          WealthSource(
            id: sourceId,
            title: 'Manual entry',
            sourceType: SourceType.manual,
            lastSyncedAt: now,
          ),
          executor: transaction,
        );
      }
      await _dao.upsertEntity(
        WealthEntity(
          id: entity.id,
          category: draft.category,
          name: draft.name,
          subtitle: draft.subtitle,
          nationalityOrOrigin: draft.nationalityOrOrigin,
          metadataJson: entity.metadataJson,
          sourceId: sourceId,
          createdAt: entity.createdAt,
          updatedAt: now,
        ),
        executor: transaction,
      );

      final keptStreamIds = <String>{};
      for (final stream in draft.incomeStreams) {
        final streamId = stream.id ?? _uuid.v4();
        keptStreamIds.add(streamId);
        await _dao.upsertIncomeStream(
          IncomeStream(
            id: streamId,
            entityId: entity.id,
            streamType: stream.streamType,
            title: stream.title,
            estimatedAnnualValue: stream.estimatedAnnualValue,
            portfolioSharePercent: stream.portfolioSharePercent,
            lastUpdatedWeek: existingStreamWeeks[streamId] ?? week,
          ),
          executor: transaction,
        );
      }
      for (final stream in previousStreams) {
        if (!keptStreamIds.contains(stream.id)) {
          await _dao.deleteIncomeStream(stream.id, executor: transaction);
        }
      }

      await _validateLinks(draft.links, entity.id, transaction);
      final keptLinkIds = <String>{};
      for (final link in draft.links) {
        final linkId = link.id ?? _uuid.v4();
        keptLinkIds.add(linkId);
        await _dao.upsertRelation(
          EntityRelation(
            id: linkId,
            fromEntityId: entity.id,
            toEntityId: link.targetId,
            relationType: link.relationType,
            relationDetail: link.relationDetail,
            sourceId: existingLinkSources[linkId] ?? sourceId,
          ),
          executor: transaction,
        );
      }
      for (final link in previousLinks) {
        if (!keptLinkIds.contains(link.id)) {
          await _dao.deleteRelation(link.id, executor: transaction);
        }
      }
    });
  }

  Future<void> _validateLinks(
    List<EntityLinkDraft> links,
    String entityId,
    DatabaseExecutor transaction,
  ) async {
    for (final link in links) {
      if (link.targetId == entityId) {
        throw const FormatException('An entity cannot be linked to itself.');
      }
      if (await _dao.getEntity(link.targetId, executor: transaction) == null) {
        throw FormatException('Linked entity ${link.targetId} does not exist.');
      }
    }
  }
}
