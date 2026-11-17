import 'package:sqflite/sqflite.dart';

import 'wealth_database.dart';
import 'wealth_models.dart';
import 'week_identifier.dart';

class WealthDao {
  const WealthDao(this._wealthDatabase);

  final WealthDatabase _wealthDatabase;

  Future<void> upsertEntity(
    WealthEntity entity, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    final row = entity.toRow();
    await db.rawInsert(
      '''
      INSERT INTO entities (
        id, category, name, subtitle, nationality_or_origin,
        metadata_json, source_id, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        category = excluded.category,
        name = excluded.name,
        subtitle = excluded.subtitle,
        nationality_or_origin = excluded.nationality_or_origin,
        metadata_json = excluded.metadata_json,
        source_id = excluded.source_id,
        updated_at = excluded.updated_at
      ''',
      [
        row['id'],
        row['category'],
        row['name'],
        row['subtitle'],
        row['nationality_or_origin'],
        row['metadata_json'],
        row['source_id'],
        row['created_at'],
        row['updated_at'],
      ],
    );
  }

  Future<void> upsertSource(
    WealthSource source, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    final row = source.toRow();
    await db.rawInsert(
      '''
      INSERT INTO sources (id, title, url, source_type, last_synced_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        url = excluded.url,
        source_type = excluded.source_type,
        last_synced_at = excluded.last_synced_at
      ''',
      [
        row['id'],
        row['title'],
        row['url'],
        row['source_type'],
        row['last_synced_at'],
      ],
    );
  }

  Future<void> upsertSnapshot(
    WeeklySnapshot snapshot, {
    DatabaseExecutor? executor,
  }) async {
    isoWeekMonday(snapshot.weekIdentifier);
    if (executor != null) {
      await _upsertSnapshot(executor, snapshot);
      return;
    }
    final db = await _wealthDatabase.database;
    await db.transaction(
      (transaction) => _upsertSnapshot(transaction, snapshot),
    );
  }

  Future<void> upsertIncomeStream(
    IncomeStream stream, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    await db.insert(
      'income_streams',
      stream.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertRelation(
    EntityRelation relation, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    await db.insert(
      'entity_relations',
      relation.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteIncomeStream(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    await db.delete('income_streams', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRelation(String id, {DatabaseExecutor? executor}) async {
    final db = executor ?? await _wealthDatabase.database;
    await db.delete('entity_relations', where: 'id = ?', whereArgs: [id]);
  }

  Future<WealthEntity?> getEntity(
    String id, {
    DatabaseExecutor? executor,
  }) async {
    final db = executor ?? await _wealthDatabase.database;
    final rows = await db.query('entities', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : WealthEntity.fromRow(rows.single);
  }

  Future<List<WealthEntity>> searchEntities(
    String query, {
    EntityCategory? category,
  }) async {
    final db = await _wealthDatabase.database;
    final conditions = <String>[];
    final arguments = <Object?>[];
    final normalized = query.trim();
    if (normalized.isNotEmpty) {
      conditions.add('(name LIKE ? OR subtitle LIKE ?)');
      arguments.addAll(['%$normalized%', '%$normalized%']);
    }
    if (category != null) {
      conditions.add('category = ?');
      arguments.add(category.value);
    }
    final rows = await db.query(
      'entities',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(WealthEntity.fromRow).toList();
  }

  Future<List<WeeklySnapshot>> snapshotsFor(String entityId) async {
    final db = await _wealthDatabase.database;
    final rows = await db.query(
      'weekly_snapshots',
      where: 'entity_id = ?',
      whereArgs: [entityId],
      orderBy: 'week_identifier',
    );
    return rows.map(WeeklySnapshot.fromRow).toList();
  }

  Future<List<IncomeStream>> incomeStreamsFor(String entityId) async {
    final db = await _wealthDatabase.database;
    final rows = await db.query(
      'income_streams',
      where: 'entity_id = ?',
      whereArgs: [entityId],
      orderBy: 'stream_type, title COLLATE NOCASE',
    );
    return rows.map(IncomeStream.fromRow).toList();
  }

  Future<List<EntityRelation>> relationsFor(String entityId) async {
    final db = await _wealthDatabase.database;
    final rows = await db.query(
      'entity_relations',
      where: 'from_entity_id = ? OR to_entity_id = ?',
      whereArgs: [entityId, entityId],
      orderBy: 'relation_type',
    );
    return rows.map(EntityRelation.fromRow).toList();
  }

  Future<WealthSource?> getSource(String id) async {
    final db = await _wealthDatabase.database;
    final rows = await db.query('sources', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : WealthSource.fromRow(rows.single);
  }

  Future<void> _upsertSnapshot(
    DatabaseExecutor executor,
    WeeklySnapshot snapshot,
  ) async {
    await executor.insert('weekly_snapshots', {
      ...snapshot.toRow(),
      'wow_change_percent': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await _recalculateWeeklyChanges(executor, snapshot.entityId);
  }

  Future<void> _recalculateWeeklyChanges(
    DatabaseExecutor executor,
    String entityId,
  ) async {
    final rows = await executor.query(
      'weekly_snapshots',
      where: 'entity_id = ?',
      whereArgs: [entityId],
      orderBy: 'week_identifier',
    );
    final byWeek = {
      for (final row in rows) row['week_identifier']! as String: row,
    };
    for (final row in rows) {
      final week = row['week_identifier']! as String;
      final previousWeek = previousIsoWeekIdentifier(week);
      final previousValue = (byWeek[previousWeek]?['total_net_worth'] as num?)
          ?.toDouble();
      final currentValue = (row['total_net_worth'] as num?)?.toDouble();
      final change = previousValue == null || previousValue == 0
          ? null
          : currentValue == null
          ? null
          : ((currentValue - previousValue) / previousValue) * 100;
      await executor.update(
        'weekly_snapshots',
        {'wow_change_percent': change},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }
}
