import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/wealth_dao.dart';
import 'package:wasl_app/data/wealth_database.dart';
import 'package:wasl_app/data/wealth_models.dart';
import 'package:wasl_app/data/wealth_mutations.dart';
import 'package:wasl_app/data/week_identifier.dart';
import 'package:wasl_app/data/weekly_bundle_importer.dart';
import 'package:wasl_app/presentation/wealth_profile_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  Future<WealthDatabase> newDatabase() async {
    final database = WealthDatabase(
      factory: databaseFactoryFfiNoIsolate,
      databasePath: inMemoryDatabasePath,
    );
    await database.database;
    return database;
  }

  Future<void> pumpProfile(
    WidgetTester tester,
    WealthDatabase database,
    String entityId,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: WealthProfilePage(entityId: entityId, database: database),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('profile shows a week-labeled trend and a merged news timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await newDatabase();
    addTearDown(database.close);
    final bundleJson = await rootBundle.loadString(
      'assets/sample_weekly_pack.json',
    );
    await WeeklyBundleImporter(database).importBundle(bundleJson);
    await pumpProfile(tester, database, 'sample_athlete_karim');

    expect(find.text('2026-W42'), findsWidgets);
    expect(find.text('2026-W46'), findsWidgets);

    const newsTitle = 'Gulf sports media rights reach a record \$1.4B package';
    expect(find.text(newsTitle), findsOneWidget);
    const latestNote =
        'The regional media-rights package revaluation added to the weekly estimate.';
    const oldestNote =
        'Pre-season bonuses and a new regional banking campaign landed.';
    expect(find.text(latestNote), findsOneWidget);
    expect(find.text(oldestNote), findsOneWidget);

    final latestY = tester.getTopLeft(find.text(latestNote)).dy;
    final oldestY = tester.getTopLeft(find.text(oldestNote)).dy;
    expect(latestY, lessThan(oldestY));
  });

  testWidgets('note-only newest week keeps the valued summary and note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await newDatabase();
    addTearDown(database.close);
    final mutations = WealthMutations(database);
    final entity = await mutations.createEntity(
      const EntityDraft(
        category: EntityCategory.athlete,
        name: 'Note Only Athlete',
        sourceTitle: 'Manual test',
      ),
    );
    await mutations.addSnapshot(
      entity: entity,
      weekIdentifier: '2026-W45',
      currencyUnit: 'USD_M',
      totalNetWorth: 420,
    );
    await mutations.addSnapshot(
      entity: entity,
      weekIdentifier: '2026-W46',
      currencyUnit: 'USD_M',
      summaryNote: 'Note only week.',
    );
    await pumpProfile(tester, database, entity.id);

    expect(find.text('\$420M'), findsOneWidget);
    expect(find.text('لا يوجد تقدير لصافي الثروة بعد'), findsNothing);
    await tester.scrollUntilVisible(find.text('Note only week.'), 400);
    expect(find.text('Note only week.'), findsOneWidget);
    expect(find.text('2026-W46'), findsWidgets);
  });

  testWidgets('editing a profile keeps its original source', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await newDatabase();
    addTearDown(database.close);
    final entity = await WealthMutations(database).createEntity(
      const EntityDraft(
        category: EntityCategory.athlete,
        name: 'Editable Athlete',
        sourceTitle: 'Original source',
        sourceUrl: 'https://example.com/original',
      ),
    );
    await pumpProfile(tester, database, entity.id);

    await tester.tap(find.byTooltip('تعديل الكيان'));
    await tester.pumpAndSettle();

    expect(find.text('تعديل الكيان'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'عنوان المصدر'), findsNothing);
    expect(
      find.textContaining('المصدر الحالي: Original source'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'الاسم'),
      'Edited Athlete',
    );
    await tester.ensureVisible(find.text('حفظ التعديلات'));
    await tester.tap(find.text('حفظ التعديلات'));
    await tester.pumpAndSettle();

    final dao = WealthDao(database);
    final updated = await dao.getEntity(entity.id);
    expect(updated?.name, 'Edited Athlete');
    expect(updated?.sourceId, entity.sourceId);
    expect((await dao.getSource(entity.sourceId!))?.title, 'Original source');
    expect(find.widgetWithText(AppBar, 'Edited Athlete'), findsOneWidget);
  });

  testWidgets('tapping a holding opens the linked asset profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = await newDatabase();
    addTearDown(database.close);
    final mutations = WealthMutations(database);
    final property = await mutations.createEntity(
      const EntityDraft(
        category: EntityCategory.propertyAsset,
        name: 'Marina Penthouse',
        subtitle: 'Waterfront residence',
        sourceTitle: 'Manual test',
      ),
    );
    final athlete = await mutations.createEntity(
      EntityDraft(
        category: EntityCategory.athlete,
        name: 'Holding Athlete',
        sourceTitle: 'Manual test',
        links: [
          EntityLinkDraft(
            targetId: property.id,
            relationType: EntityRelationType.ownsProperty,
            relationDetail: '100% ownership',
          ),
        ],
      ),
    );
    await pumpProfile(tester, database, athlete.id);

    final holding = find.widgetWithText(ListTile, 'Marina Penthouse');
    expect(holding, findsOneWidget);
    await tester.ensureVisible(holding);
    await tester.tap(holding);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Marina Penthouse'), findsOneWidget);
    expect(find.text('Waterfront residence'), findsOneWidget);
    expect(find.byTooltip('تعديل الكيان'), findsOneWidget);
  });

  testWidgets('adds a weekly update from the profile', (tester) async {
    final database = await newDatabase();
    addTearDown(database.close);
    final entity = await WealthMutations(database).createEntity(
      const EntityDraft(
        category: EntityCategory.athlete,
        name: 'Update Athlete',
        sourceTitle: 'Manual test',
      ),
    );
    await pumpProfile(tester, database, entity.id);

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'إضافة تحديث أسبوعي'),
    );
    await tester.pumpAndSettle();
    expect(find.text('تحديث أسبوعي جديد'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'صافي الثروة'),
      '820.5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'ملاحظة أسبوعية (اختياري)'),
      'Signed a new endorsement.',
    );
    await tester.ensureVisible(find.text('حفظ التحديث'));
    await tester.tap(find.text('حفظ التحديث'));
    await tester.pumpAndSettle();

    expect(find.text('\$820.5M'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Signed a new endorsement.'),
      400,
    );
    expect(find.text('Signed a new endorsement.'), findsOneWidget);

    final snapshots = await WealthDao(database).snapshotsFor(entity.id);
    expect(snapshots, hasLength(1));
    expect(snapshots.single.weekIdentifier, currentIsoWeekIdentifier());
    expect(snapshots.single.totalNetWorth, 820.5);
    expect(snapshots.single.currencyUnit, 'USD_M');
  });
}
