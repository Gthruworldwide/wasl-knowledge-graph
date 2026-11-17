import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/wealth_dao.dart';
import 'package:wasl_app/data/wealth_database.dart';
import 'package:wasl_app/data/wealth_models.dart';
import 'package:wasl_app/data/weekly_bundle_importer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  Future<WealthDatabase> newDatabase() async {
    final database = WealthDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await database.database;
    return database;
  }

  test(
    'weekly snapshots calculate and recalculate week-over-week change',
    () async {
      final database = await newDatabase();
      addTearDown(database.close);
      final dao = WealthDao(database);
      const time = '2026-11-17T00:00:00.000Z';

      await dao.upsertEntity(
        const WealthEntity(
          id: 'person-1',
          category: EntityCategory.athlete,
          name: 'Fictional Athlete',
          createdAt: time,
          updatedAt: time,
        ),
      );
      await dao.upsertSource(
        const WealthSource(
          id: 'source-1',
          title: 'Manual test source',
          sourceType: SourceType.manual,
          lastSyncedAt: time,
        ),
      );

      WeeklySnapshot snapshot(String week, double netWorth) => WeeklySnapshot(
        id: '$week-person',
        entityId: 'person-1',
        weekIdentifier: week,
        recordedAt: time,
        totalNetWorth: netWorth,
        currencyUnit: 'USD_M',
        sourceId: 'source-1',
      );

      await dao.upsertSnapshot(snapshot('2026-W46', 100));
      await dao.upsertSnapshot(snapshot('2026-W47', 110));
      await dao.upsertSnapshot(snapshot('2026-W48', 99));

      var snapshots = await dao.snapshotsFor('person-1');
      expect(snapshots[0].wowChangePercent, isNull);
      expect(snapshots[1].wowChangePercent, closeTo(10, 0.0001));
      expect(snapshots[2].wowChangePercent, closeTo(-10, 0.0001));

      await dao.upsertSnapshot(snapshot('2026-W47', 120));
      snapshots = await dao.snapshotsFor('person-1');
      expect(snapshots[1].wowChangePercent, closeTo(20, 0.0001));
      expect(snapshots[2].wowChangePercent, closeTo(-17.5, 0.0001));
    },
  );

  test('weekly JSON seed imports atomically and is idempotent', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final weeklyImporter = WeeklyBundleImporter(database);
    final bundleJson = await rootBundle.loadString(
      'assets/seed/weekly_bundle_v2.json',
    );

    final summary = await weeklyImporter.importBundle(bundleJson);
    expect(summary.entityCount, 5);
    expect(summary.snapshotCount, 5);
    expect(summary.incomeStreamCount, 6);
    expect(summary.relationCount, 4);
    expect(
      (await WealthDao(
        database,
      ).searchEntities('', category: EntityCategory.artist)).single.name,
      'Fictional Artist One',
    );
    final db = await database.database;
    final importedEntities = await db.query('entities');
    expect(
      importedEntities.every(
        (entity) => entity['source_id'] == summary.sourceId,
      ),
      isTrue,
    );
    final importedRelations = await db.query('entity_relations');
    expect(
      importedRelations.every(
        (relation) => relation['source_id'] == summary.sourceId,
      ),
      isTrue,
    );

    final repeatedSummary = await weeklyImporter.importBundle(bundleJson);
    expect(repeatedSummary.sourceId, summary.sourceId);
    expect(await db.query('entities'), hasLength(5));
    expect(await db.query('weekly_snapshots'), hasLength(5));
    expect(await db.query('income_streams'), hasLength(6));
    expect(await db.query('entity_relations'), hasLength(4));

    final before = await db.query('entities');
    final malformedReference = jsonDecode(bundleJson) as Map<String, dynamic>;
    final firstEntity =
        (malformedReference['entities'] as List).first as Map<String, dynamic>;
    firstEntity['relations'] = [
      {'targetId': 'missing_target', 'relationType': 'OWNS_PROPERTY'},
    ];
    await expectLater(
      weeklyImporter.importBundle(jsonEncode(malformedReference)),
      throwsFormatException,
    );
    expect(await db.query('entities'), hasLength(before.length));
    expect(await db.query('entity_relations'), hasLength(4));
  });

  test('sample weekly pack imports multi-week history and relations', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final weeklyImporter = WeeklyBundleImporter(database);
    final bundleJson = await rootBundle.loadString(
      'assets/sample_weekly_pack.json',
    );

    final summary = await weeklyImporter.importBundle(bundleJson);
    expect(summary.entityCount, 5);
    expect(summary.snapshotCount, 22);
    expect(summary.incomeStreamCount, 9);
    expect(summary.relationCount, 6);

    final dao = WealthDao(database);
    final athlete = await dao.getEntity('sample_athlete_karim');
    expect(athlete?.category, EntityCategory.athlete);
    final athleteSnapshots = await dao.snapshotsFor(athlete!.id);
    expect(athleteSnapshots.map((snapshot) => snapshot.weekIdentifier), [
      '2026-W42',
      '2026-W43',
      '2026-W44',
      '2026-W45',
      '2026-W46',
    ]);
    expect(athleteSnapshots.first.wowChangePercent, isNull);
    expect(
      athleteSnapshots.last.wowChangePercent,
      closeTo((186.4 - 183.9) / 183.9 * 100, 0.0001),
    );

    final athleteRelations = await dao.relationsFor(athlete.id);
    expect(
      athleteRelations.map((relation) => relation.relationType),
      containsAll([
        EntityRelationType.ownsProperty,
        EntityRelationType.sponsoredBy,
        EntityRelationType.impactedByNews,
      ]),
    );
    expect(
      athleteRelations
          .where(
            (relation) =>
                relation.relationType == EntityRelationType.ownsProperty,
          )
          .single
          .toEntityId,
      'sample_property_azure_palm',
    );

    final news = await dao.getEntity('sample_news_media_rights');
    expect(news?.category, EntityCategory.economicNews);
    final newsSnapshots = await dao.snapshotsFor(news!.id);
    expect(newsSnapshots, hasLength(2));
    expect(
      newsSnapshots.every((snapshot) => snapshot.totalNetWorth == null),
      isTrue,
    );

    final repeatedSummary = await weeklyImporter.importBundle(bundleJson);
    expect(repeatedSummary.sourceId, summary.sourceId);
    final db = await database.database;
    expect(await db.query('entities'), hasLength(5));
    expect(await db.query('weekly_snapshots'), hasLength(22));
    expect(await db.query('income_streams'), hasLength(9));
    expect(await db.query('entity_relations'), hasLength(6));
  });

  test('rejects duplicate snapshot weeks for one entity', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final weeklyImporter = WeeklyBundleImporter(database);
    final bundle = {
      'bundleVersion': '2.0',
      'weekIdentifier': '2026-W46',
      'generatedAt': '2026-11-17T00:00:00Z',
      'source': {'title': 'Duplicate week test', 'sourceType': 'JSON_IMPORT'},
      'entities': [
        {
          'id': 'duplicate-week-entity',
          'category': 'ATHLETE',
          'name': 'Duplicate Week',
          'snapshots': [
            {
              'weekIdentifier': '2026-W45',
              'totalNetWorth': 10,
              'currencyUnit': 'USD_M',
            },
            {
              'weekIdentifier': '2026-W45',
              'totalNetWorth': 11,
              'currencyUnit': 'USD_M',
            },
          ],
        },
      ],
    };

    await expectLater(
      weeklyImporter.importBundle(jsonEncode(bundle)),
      throwsFormatException,
    );
    final db = await database.database;
    expect(await db.query('entities'), isEmpty);
    expect(await db.query('weekly_snapshots'), isEmpty);
  });

  test('rejects invalid currency units and stream week metadata', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final weeklyImporter = WeeklyBundleImporter(database);
    Map<String, dynamic> bundle({
      String currencyUnit = 'USD_M',
      String lastUpdatedWeek = '2026-W46',
      bool selfRelation = false,
    }) => {
      'bundleVersion': '2.0',
      'weekIdentifier': '2026-W46',
      'generatedAt': '2026-11-17T00:00:00Z',
      'source': {'title': 'Validation test', 'sourceType': 'JSON_IMPORT'},
      'entities': [
        {
          'id': 'validation-entity',
          'category': 'ATHLETE',
          'name': 'Validation Athlete',
          'snapshots': [
            {
              'weekIdentifier': '2026-W46',
              'totalNetWorth': 10,
              'currencyUnit': currencyUnit,
            },
          ],
          'incomeStreams': [
            {
              'streamType': 'SALARY_CONTRACT',
              'title': 'Deal',
              'lastUpdatedWeek': lastUpdatedWeek,
            },
          ],
          if (selfRelation)
            'relations': [
              {
                'targetId': 'validation-entity',
                'relationType': 'OWNS_PROPERTY',
              },
            ],
        },
      ],
    };

    await expectLater(
      weeklyImporter.importBundle(jsonEncode(bundle(currencyUnit: 'EUR'))),
      throwsFormatException,
    );
    await expectLater(
      weeklyImporter.importBundle(
        jsonEncode(bundle(lastUpdatedWeek: '2026-W54')),
      ),
      throwsFormatException,
    );
    await expectLater(
      weeklyImporter.importBundle(jsonEncode(bundle(selfRelation: true))),
      throwsFormatException,
    );

    final db = await database.database;
    expect(await db.query('entities'), isEmpty);
    expect(await db.query('weekly_snapshots'), isEmpty);
    expect(await db.query('income_streams'), isEmpty);
    expect(await db.query('entity_relations'), isEmpty);
  });

  test('rejects invalid ISO week identifiers', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final dao = WealthDao(database);
    await expectLater(
      dao.upsertSnapshot(
        const WeeklySnapshot(
          id: 'invalid-week',
          entityId: 'missing-entity',
          weekIdentifier: '2026-W54',
          recordedAt: '2026-11-17T00:00:00Z',
          currencyUnit: 'USD_M',
          sourceId: 'missing-source',
        ),
      ),
      throwsFormatException,
    );
  });

  test(
    'upgrades existing v1 records with source and valid-time columns',
    () async {
      final path = p.join(
        Directory.systemTemp.path,
        'wasl_v1_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('CREATE TABLE sources (id TEXT PRIMARY KEY)');
            await db.execute('CREATE TABLE entities (id TEXT PRIMARY KEY)');
            await db.execute(
              'CREATE TABLE entity_relations (id TEXT PRIMARY KEY)',
            );
            await db.insert('entities', {'id': 'existing-entity'});
            await db.insert('entity_relations', {'id': 'existing-relation'});
          },
        ),
      );
      await oldDatabase.close();

      final database = WealthDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(() async {
        await database.close();
        await databaseFactoryFfi.deleteDatabase(path);
      });
      final upgraded = await database.database;
      final entityColumns = await upgraded.rawQuery(
        'PRAGMA table_info(entities)',
      );
      final relationColumns = await upgraded.rawQuery(
        'PRAGMA table_info(entity_relations)',
      );

      expect(
        entityColumns.map((column) => column['name']),
        contains('source_id'),
      );
      expect(
        relationColumns.map((column) => column['name']),
        containsAll(['source_id', 'valid_from', 'valid_to']),
      );
      expect(await upgraded.query('entities'), hasLength(1));
      expect(await upgraded.query('entity_relations'), hasLength(1));
    },
  );
}
