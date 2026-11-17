import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/wealth_dao.dart';
import 'package:wasl_app/data/wealth_database.dart';
import 'package:wasl_app/data/wealth_models.dart';
import 'package:wasl_app/data/wealth_mutations.dart';
import 'package:wasl_app/data/week_identifier.dart';

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

  test('creates and edits an entity with streams and property links', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final mutations = WealthMutations(database);
    final dao = WealthDao(database);

    final property = await mutations.createEntity(
      const EntityDraft(
        category: EntityCategory.propertyAsset,
        name: 'Test Villa',
        sourceTitle: 'Manual test',
      ),
    );
    final athlete = await mutations.createEntity(
      EntityDraft(
        category: EntityCategory.athlete,
        name: 'Test Athlete',
        subtitle: 'Footballer',
        sourceTitle: 'Manual test',
        incomeStreams: const [
          IncomeStreamDraft(
            streamType: IncomeStreamType.salaryContract,
            title: 'Club contract',
            estimatedAnnualValue: 20,
            portfolioSharePercent: 60,
          ),
          IncomeStreamDraft(
            streamType: IncomeStreamType.endorsementsAds,
            title: 'Sponsorship',
            estimatedAnnualValue: 10,
            portfolioSharePercent: 40,
          ),
        ],
        links: [
          EntityLinkDraft(
            targetId: property.id,
            relationType: EntityRelationType.ownsProperty,
            relationDetail: '100% ownership',
          ),
        ],
      ),
    );

    final createdRow = await dao.getEntity(athlete.id);
    expect(createdRow?.name, 'Test Athlete');
    expect(createdRow?.sourceId, isNotNull);
    final created = createdRow!;
    var streams = await dao.incomeStreamsFor(athlete.id);
    expect(streams, hasLength(2));
    expect(
      streams.map((stream) => stream.portfolioSharePercent),
      containsAll([60.0, 40.0]),
    );
    var relations = await dao.relationsFor(athlete.id);
    expect(relations, hasLength(1));
    expect(relations.single.relationType, EntityRelationType.ownsProperty);
    expect(relations.single.toEntityId, property.id);
    expect(relations.single.sourceId, created.sourceId);

    final retained = streams.firstWhere(
      (stream) => stream.title == 'Club contract',
    );
    await mutations.updateEntity(
      entity: created,
      draft: EntityDraft(
        category: EntityCategory.athlete,
        name: 'Test Athlete Updated',
        subtitle: 'Footballer and founder',
        incomeStreams: [
          IncomeStreamDraft(
            id: retained.id,
            streamType: IncomeStreamType.salaryContract,
            title: 'Club contract',
            estimatedAnnualValue: 25,
            portfolioSharePercent: 50,
          ),
          const IncomeStreamDraft(
            streamType: IncomeStreamType.businessEquity,
            title: 'Academy equity',
            estimatedAnnualValue: 5,
            portfolioSharePercent: 50,
          ),
        ],
      ),
      previousStreams: streams,
      previousLinks: relations,
    );

    final updated = await dao.getEntity(athlete.id);
    streams = await dao.incomeStreamsFor(athlete.id);
    expect(updated?.name, 'Test Athlete Updated');
    expect(updated?.subtitle, 'Footballer and founder');
    expect(updated?.createdAt, athlete.createdAt);
    expect(streams, hasLength(2));
    expect(
      streams.map((stream) => stream.title),
      containsAll(['Club contract', 'Academy equity']),
    );
    expect(
      streams.map((stream) => stream.title),
      isNot(contains('Sponsorship')),
    );
    expect(
      streams
          .firstWhere((stream) => stream.id == retained.id)
          .estimatedAnnualValue,
      25,
    );
    relations = await dao.relationsFor(athlete.id);
    expect(relations, isEmpty);
  });

  test('current week identifier follows ISO week rules', () {
    expect(currentIsoWeekIdentifier(DateTime.utc(2026, 11, 17)), '2026-W47');
    expect(currentIsoWeekIdentifier(DateTime.utc(2026, 1, 1)), '2026-W01');
  });

  test(
    'adds weekly snapshots, recalculates WoW, and rejects duplicates',
    () async {
      final database = await newDatabase();
      addTearDown(database.close);
      final mutations = WealthMutations(database);
      final dao = WealthDao(database);

      final entity = await mutations.createEntity(
        const EntityDraft(
          category: EntityCategory.athlete,
          name: 'Weekly Athlete',
          sourceTitle: 'Manual test',
        ),
      );

      await mutations.addSnapshot(
        entity: entity,
        weekIdentifier: '2026-W45',
        currencyUnit: 'USD_M',
        totalNetWorth: 100,
        summaryNote: 'Opening estimate',
      );
      await mutations.addSnapshot(
        entity: entity,
        weekIdentifier: '2026-W46',
        currencyUnit: 'USD_M',
        totalNetWorth: 110,
        summaryNote: 'New endorsement',
      );

      final snapshots = await dao.snapshotsFor(entity.id);
      expect(snapshots, hasLength(2));
      expect(snapshots.first.wowChangePercent, isNull);
      expect(snapshots.last.wowChangePercent, closeTo(10, 0.0001));
      expect(snapshots.last.summaryNote, 'New endorsement');
      expect(snapshots.last.sourceId, entity.sourceId);

      await expectLater(
        mutations.addSnapshot(
          entity: entity,
          weekIdentifier: '2026-W46',
          currencyUnit: 'USD_M',
          totalNetWorth: 120,
          summaryNote: 'Overwrite attempt',
        ),
        throwsFormatException,
      );
      final unchanged = await dao.snapshotsFor(entity.id);
      expect(unchanged, hasLength(2));
      expect(unchanged.last.totalNetWorth, 110);
      expect(unchanged.last.summaryNote, 'New endorsement');

      await expectLater(
        mutations.addSnapshot(
          entity: entity,
          weekIdentifier: '2026-W47',
          currencyUnit: 'EUR',
          totalNetWorth: 120,
        ),
        throwsFormatException,
      );
      expect(await dao.snapshotsFor(entity.id), hasLength(2));
    },
  );

  test('rejects linking a missing entity without partial writes', () async {
    final database = await newDatabase();
    addTearDown(database.close);
    final mutations = WealthMutations(database);
    final dao = WealthDao(database);

    await expectLater(
      mutations.createEntity(
        const EntityDraft(
          category: EntityCategory.athlete,
          name: 'Broken Link Athlete',
          sourceTitle: 'Manual test',
          incomeStreams: [
            IncomeStreamDraft(
              streamType: IncomeStreamType.salaryContract,
              title: 'Club contract',
            ),
          ],
          links: [
            EntityLinkDraft(
              targetId: 'missing-entity',
              relationType: EntityRelationType.ownsProperty,
            ),
          ],
        ),
      ),
      throwsFormatException,
    );

    expect(await dao.searchEntities(''), isEmpty);
    final db = await database.database;
    expect(await db.query('income_streams'), isEmpty);
    expect(await db.query('entity_relations'), isEmpty);
  });
}
