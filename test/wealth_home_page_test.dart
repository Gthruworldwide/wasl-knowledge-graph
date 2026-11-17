import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/wealth_dao.dart';
import 'package:wasl_app/data/wealth_database.dart';
import 'package:wasl_app/data/wealth_models.dart';
import 'package:wasl_app/data/wealth_mutations.dart';
import 'package:wasl_app/presentation/wealth_home_page.dart';

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

  Future<void> pumpHome(WidgetTester tester, WealthDatabase database) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: WealthHomePage(database: database, onLocaleChanged: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'wealth filter bar starts with All and sample pack fills the feed',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = await newDatabase();
      addTearDown(database.close);
      await pumpHome(tester, database);

      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('استيراد حزمة بيانات تجريبية'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);

      var chips = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .toList();
      expect(chips, hasLength(EntityCategory.values.length + 1));
      expect(chips.map((chip) => (chip.label as Text).data).toList(), [
        'الكل',
        'اللاعبون',
        'الفنانون',
        'شخصيات الأعمال',
        'الشركات',
        'الممتلكات',
        'الأخبار الاقتصادية',
      ]);
      expect(chips.first.selected, isTrue);

      await tester.tap(
        find.widgetWithText(OutlinedButton, 'استيراد حزمة بيانات تجريبية'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('من الحزمة التجريبية'), findsOneWidget);
      expect(find.text('Azure Palm Villa'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'الفنانون'));
      await tester.pumpAndSettle();

      expect(find.text('Layla Nasser'), findsOneWidget);
      expect(find.text('Azure Palm Villa'), findsNothing);
      chips = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      expect(
        chips
            .firstWhere((chip) => (chip.label as Text).data == 'الكل')
            .selected,
        isFalse,
      );

      await tester.tap(find.widgetWithText(FilterChip, 'الكل'));
      await tester.pumpAndSettle();

      expect(find.text('Azure Palm Villa'), findsOneWidget);
    },
  );

  testWidgets('manual add sheet exposes income streams and holdings', (
    tester,
  ) async {
    final database = await newDatabase();
    addTearDown(database.close);
    await pumpHome(tester, database);

    await tester.tap(find.widgetWithText(FilledButton, 'إضافة كيان'));
    await tester.pumpAndSettle();

    expect(find.text('كيان جديد'), findsOneWidget);
    expect(find.text('مصادر الدخل'), findsOneWidget);
    expect(find.text('إضافة مصدر'), findsOneWidget);
    expect(find.text('الممتلكات والحصص المرتبطة'), findsOneWidget);
    expect(
      find.text('لا توجد مصادر دخل بعد. أضف مصدرًا وحدد نسبته من المحفظة.'),
      findsOneWidget,
    );

    await tester.tap(find.text('إضافة مصدر'));
    await tester.pumpAndSettle();

    expect(find.text('نوع المصدر'), findsOneWidget);
    expect(find.text('نسبة المحفظة %'), findsOneWidget);
  });

  testWidgets('saving manual entity persists its stream and property link', (
    tester,
  ) async {
    final database = await newDatabase();
    addTearDown(database.close);
    final property = await WealthMutations(database).createEntity(
      const EntityDraft(
        category: EntityCategory.propertyAsset,
        name: 'Marina Penthouse',
        sourceTitle: 'Manual test',
      ),
    );
    final dao = WealthDao(database);
    await pumpHome(tester, database);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'إضافة كيان'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'الاسم'),
      'Omar Haddad',
    );
    await tester.tap(find.text('الفئة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اللاعبون').last);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('إضافة مصدر'));
    await tester.tap(find.text('إضافة مصدر'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'الوصف'),
      'Club contract',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'نسبة المحفظة %'),
      '55',
    );

    await tester.ensureVisible(find.text('ربط عقار أو شركة موجودة'));
    await tester.tap(find.text('ربط عقار أو شركة موجودة'));
    await tester.pumpAndSettle();
    expect(find.text('Marina Penthouse'), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'ربط'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('حفظ الكيان'));
    await tester.tap(find.text('حفظ الكيان'));
    await tester.pumpAndSettle();

    final saved = (await dao.searchEntities('Omar Haddad')).single;
    expect(saved.category, EntityCategory.athlete);
    expect(saved.sourceId, isNotNull);

    final streams = await dao.incomeStreamsFor(saved.id);
    expect(streams, hasLength(1));
    expect(streams.single.title, 'Club contract');
    expect(streams.single.portfolioSharePercent, 55);

    final relations = await dao.relationsFor(saved.id);
    expect(relations, hasLength(1));
    expect(relations.single.relationType, EntityRelationType.ownsProperty);
    expect(relations.single.toEntityId, property.id);

    expect(find.text('Omar Haddad'), findsWidgets);
  });

  testWidgets('note-only newest week keeps the latest valued amount', (
    tester,
  ) async {
    final database = await newDatabase();
    addTearDown(database.close);
    final mutations = WealthMutations(database);
    final entity = await mutations.createEntity(
      const EntityDraft(
        category: EntityCategory.athlete,
        name: 'Valued Athlete',
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
    await pumpHome(tester, database);

    expect(find.text('\$420M'), findsOneWidget);
    expect(find.text('لا يوجد تقدير بعد'), findsNothing);
  });

  testWidgets('income tags show the largest portfolio shares first', (
    tester,
  ) async {
    final database = await newDatabase();
    addTearDown(database.close);
    await WealthMutations(database).createEntity(
      const EntityDraft(
        category: EntityCategory.athlete,
        name: 'Share Order Athlete',
        sourceTitle: 'Manual test',
        incomeStreams: [
          IncomeStreamDraft(
            streamType: IncomeStreamType.realEstate,
            title: 'Rental portfolio',
            portfolioSharePercent: 70,
          ),
          IncomeStreamDraft(
            streamType: IncomeStreamType.salaryContract,
            title: 'Small contract',
            portfolioSharePercent: 30,
          ),
          IncomeStreamDraft(
            streamType: IncomeStreamType.endorsementsAds,
            title: 'Small campaign',
            portfolioSharePercent: 20,
          ),
        ],
      ),
    );
    await pumpHome(tester, database);

    final chips = tester.widgetList<Chip>(find.byType(Chip)).toList();
    expect(chips, hasLength(2));
    expect((chips[0].label as Text).data, '70% عقارات');
    expect((chips[1].label as Text).data, '30% عقود');
  });
}
