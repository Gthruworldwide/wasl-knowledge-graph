import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/imf_cpi_catalog.dart';
import 'package:wasl_app/data/imf_observation.dart';
import 'package:wasl_app/data/imf_repository.dart';
import 'package:wasl_app/data/imf_sdmx_client.dart';
import 'package:wasl_app/data/wealth_dao.dart';
import 'package:wasl_app/data/wealth_database.dart';
import 'package:wasl_app/data/wealth_models.dart';

const String sampleDataMessage = '''
{
  "header": {
    "id": "DS-TEST",
    "prepared": "2026-11-17T18:00:00Z",
    "sender": {"id": "IMF", "name": "unknown"}
  },
  "dataSets": [{
    "action": "Replace",
    "series": {
      "0:0:0:0:0": {
        "attributes": [],
        "observations": {"0": ["3.5"], "1": ["4.2"]}
      },
      "1:0:0:0:0": {
        "attributes": [],
        "observations": {"0": ["2.1"], "1": ["nan"]}
      }
    }
  }],
  "structure": {
    "name": "Consumer Price Index (CPI)",
    "dimensions": {
      "dataset": [],
      "series": [
        {
          "id": "COUNTRY", "name": "Country", "keyPosition": 0,
          "values": [
            {"id": "USA", "name": "United States"},
            {"id": "GBR", "name": "United Kingdom"}
          ]
        },
        {
          "id": "INDEX_TYPE", "name": "Index type", "keyPosition": 1,
          "values": [{"id": "CPI", "name": "Consumer price index (CPI)"}]
        },
        {
          "id": "COICOP_1999", "name": "Expenditure Category", "keyPosition": 2,
          "values": [{"id": "_T", "name": "All Items"}]
        },
        {
          "id": "TYPE_OF_TRANSFORMATION", "name": "Type of Transformation",
          "keyPosition": 3,
          "values": [{"id": "YOY_PCH_PA_PT", "name": "Year-over-year percent"}]
        },
        {
          "id": "FREQUENCY", "name": "Frequency", "keyPosition": 4,
          "values": [{"id": "M", "name": "Monthly"}]
        }
      ],
      "observation": [
        {
          "id": "TIME_PERIOD", "name": "Time Period", "keyPosition": 5,
          "role": "time",
          "values": [
            {"id": "2026-M08", "name": "2026-M08"},
            {"id": "2026-M09", "name": "2026-M09"}
          ]
        }
      ]
    }
  }
}
''';

const String sampleV30DataMessage = '''
{
  "meta": {},
  "data": {
    "dataSets": [
      {
        "structure": 0,
        "action": "Replace",
        "series": {
          "0:0:0:0:0": {
            "attributes": [0, null, 0, null, "true"],
            "observations": {
              "0": ["3.40", null, 0, null, null],
              "1": ["3.70", null, 0, null, null]
            }
          }
        }
      }
    ],
    "structures": [
      {
        "dataSets": [0],
        "dimensions": {
          "series": [
            {
              "id": "COUNTRY", "keyPosition": 0, "roles": [],
              "values": [{"id": "USA"}]
            },
            {
              "id": "INDEX_TYPE", "keyPosition": 1, "roles": [],
              "values": [{"id": "CPI"}]
            },
            {
              "id": "COICOP_1999", "keyPosition": 2, "roles": [],
              "values": [{"id": "_T"}]
            },
            {
              "id": "TYPE_OF_TRANSFORMATION", "keyPosition": 3, "roles": [],
              "values": [{"id": "YOY_PCH_PA_PT"}]
            },
            {
              "id": "FREQUENCY", "keyPosition": 4, "roles": ["FREQ"],
              "values": [{"id": "M"}]
            }
          ],
          "observation": [
            {
              "id": "TIME_PERIOD", "keyPosition": 5,
              "values": [{"value": "2026-M08"}, {"value": "2026-M09"}]
            }
          ]
        }
      }
    ]
  }
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  group('ImfSdmxClient', () {
    test('builds SDMX data, structure and availability URLs', () {
      final client = ImfSdmxClient();

      final data = client.dataUri(
        flowRef: ImfCpiCatalog.flowRef,
        key: ImfCpiCatalog.keyFor(['USA', 'GBR']),
        providerRef: 'all',
        startPeriod: '2022',
      );
      expect(data.pathSegments, [
        'external', 'sdmx', '2.1', 'data', 'IMF.STA,CPI',
        'USA+GBR.CPI._T.YOY_PCH_PA_PT.M', 'all',
      ]);
      expect(data.queryParameters['startPeriod'], '2022');
      expect(data.queryParameters['dimensionAtObservation'], 'TIME_PERIOD');
      expect(data.queryParameters['detail'], 'dataonly');
      expect(data.queryParameters['includeHistory'], 'false');

      final structure = client.structureUri(
        structureType: 'codelist',
        agencyID: 'IMF.STA',
        resourceID: 'CL_CPI_TYPE_OF_TRANSFORMATION',
        versionId: 'latest',
      );
      expect(structure.pathSegments.last, 'latest');
      expect(
        structure.pathSegments,
        contains('CL_CPI_TYPE_OF_TRANSFORMATION'),
      );
      expect(structure.queryParameters['references'], 'none');

      final availability = client.availabilityUri(
        flowRef: ImfCpiCatalog.flowRef,
        key: 'all',
        providerRef: 'all',
        componentID: 'COUNTRY',
      );
      expect(availability.pathSegments.last, 'COUNTRY');
      expect(availability.pathSegments, contains('availableconstraint'));
    });

    test('parses compact SDMX-JSON series and skips missing values', () {
      final message = ImfSdmxClient().parsePayload(sampleDataMessage);

      expect(message.name, 'Consumer Price Index (CPI)');
      expect(message.senderId, 'IMF');
      expect(message.series, hasLength(2));
      expect(message.series.first.code('COUNTRY'), 'USA');
      expect(message.series.first.name('COUNTRY'), 'United States');
      expect(
        message.series.first.observations
            .map((observation) => observation.period),
        ['2026-M08', '2026-M09'],
      );
      expect(
        message.series.first.observations.last.value,
        closeTo(4.2, 0.0001),
      );
      expect(message.series.last.observations, hasLength(1));
      expect(message.series.last.code('COUNTRY'), 'GBR');
    });

    test('builds SDMX 3.0 data, structure, availability and metadata URLs',
        () {
      final client = ImfSdmxClient(version: ImfApiVersion.v30);
      final key = ImfCpiCatalog.keyFor(['USA']);
      final flowRef = ImfCpiCatalog.flowRefFor(ImfApiVersion.v30);

      final data = client.dataUri(
        flowRef: flowRef,
        key: key,
        startPeriod: '2025',
        lastNObservations: 2,
      );
      expect(data.pathSegments, [
        'external',
        'sdmx',
        '3.0',
        'data',
        'dataflow',
        'IMF.STA',
        'CPI',
        '5.0.0',
        key,
      ]);
      expect(data.queryParameters['lastNObservations'], '2');

      final structure = client.structureUri(
        structureType: 'codelist',
        agencyID: 'IMF.STA',
        resourceID: 'CL_CPI_TYPE_OF_TRANSFORMATION',
        versionId: 'latest',
      );
      expect(structure.pathSegments, [
        'external',
        'sdmx',
        '3.0',
        'structure',
        'codelist',
        'IMF.STA',
        'CL_CPI_TYPE_OF_TRANSFORMATION',
        'latest',
      ]);

      final availability = client.availabilityUri(
        flowRef: flowRef,
        key: key,
        providerRef: ImfCpiCatalog.providerRef,
        componentID: 'COUNTRY',
      );
      expect(availability.pathSegments, contains('availability'));
      expect(availability.pathSegments, contains('dataflow'));
      expect(availability.pathSegments, contains('5.0.0'));
      expect(availability.pathSegments.last, 'COUNTRY');

      expect(
        client.metadataStructureUri(
          structureType: 'codelist',
          agencyID: 'IMF.STA',
          resourceID: 'CL_CPI_TYPE_OF_TRANSFORMATION',
          versionId: 'latest',
        ).pathSegments,
        [
          'external',
          'sdmx',
          '3.0',
          'metadata',
          'structure',
          'codelist',
          'IMF.STA',
          'CL_CPI_TYPE_OF_TRANSFORMATION',
          'latest',
        ],
      );
      expect(
        client.metadataFlowUri(
          agencyID: 'IMF.STA',
          resourceID: 'CPI',
          versionId: 'latest',
        ).pathSegments,
        [
          'external',
          'sdmx',
          '3.0',
          'metadata',
          'metadataflow',
          'IMF.STA',
          'CPI',
          'latest',
          'all',
        ],
      );
      expect(
        client.metaDataSetUri(
          providerId: 'IMF.STA',
          resourceID: 'CPI',
          versionId: '5.0.0',
        ).pathSegments,
        [
          'external',
          'sdmx',
          '3.0',
          'metadata',
          'metadataset',
          'IMF.STA',
          'CPI',
          '5.0.0',
        ],
      );
    });

    test('metadata URLs are unavailable on SDMX 2.1', () {
      final client = ImfSdmxClient();
      expect(
        () => client.fetchMetadataFlow(agencyID: 'IMF.STA', resourceID: 'CPI'),
        throwsUnsupportedError,
      );
    });

    test('parses wrapped, indexed SDMX 3.0 data messages', () {
      final message =
          ImfSdmxClient(version: ImfApiVersion.v30).parsePayload(
        sampleV30DataMessage,
      );

      expect(message.series, hasLength(1));
      expect(message.series.single.code('COUNTRY'), 'USA');
      expect(
        message.series.single.observations
            .map((observation) => observation.period),
        ['2026-M08', '2026-M09'],
      );
      expect(
        message.series.single.observations.last.value,
        closeTo(3.7, 0.0001),
      );
    });

    test('surfaces non-200 responses as ImfApiException', () async {
      final client = ImfSdmxClient(
        client: MockClient((_) async => http.Response('nope', 503)),
      );
      expect(
        () => client.fetchData(
          flowRef: 'IMF.STA,CPI',
          key: 'all',
        ),
        throwsA(
          isA<ImfApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    });
  });

  group('ImfRepository', () {
    Future<WealthDatabase> newDatabase() async {
      final database = WealthDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      await database.database;
      return database;
    }

    test('imports CPI observations, news notes and links idempotently',
        () async {
      SharedPreferences.setMockInitialValues({});
      final database = await newDatabase();
      addTearDown(database.close);
      final dao = WealthDao(database);
      const time = '2026-11-17T00:00:00.000Z';
      await dao.upsertEntity(
        const WealthEntity(
          id: 'person-1',
          category: EntityCategory.athlete,
          name: 'Fictional Athlete',
          nationalityOrOrigin: 'United States',
          createdAt: time,
          updatedAt: time,
        ),
      );

      final requests = <Uri>[];
      final mock = MockClient((request) async {
        requests.add(request.url);
        expect(request.headers['Accept'], 'application/json');
        return http.Response(sampleDataMessage, 200);
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = ImfRepository(
        database,
        client: ImfSdmxClient(client: mock),
        preferences: preferences,
      );

      final summary = await repository.importCpi(
        countryCodes: ['USA', 'GBR'],
        startYear: 2024,
      );
      expect(summary.countryCount, 2);
      expect(summary.observationCount, 3);
      expect(summary.newsCount, 2);
      expect(summary.linkedEntityCount, 1);
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters['startPeriod'], '2024');

      final latest = await repository.latestObservations();
      expect(latest, hasLength(2));
      final usa = latest.firstWhere((item) => item.countryCode == 'USA');
      expect(usa.value, closeTo(4.2, 0.0001));
      expect(usa.period, '2026-M09');
      expect((await repository.historyFor('USA')), hasLength(2));

      final news = await dao.searchEntities('', category: EntityCategory.economicNews);
      expect(news, hasLength(2));
      final usaNews = news.firstWhere(
        (entity) => entity.metadataJson.contains('"countryCode":"USA"'),
      );
      final snapshots = await dao.snapshotsFor(usaNews.id);
      expect(snapshots, hasLength(2));
      expect(snapshots.every((item) => item.totalNetWorth == null), isTrue);
      expect(
        snapshots.map((item) => item.summaryNote),
        everyElement(contains('% YoY')),
      );
      expect(
        snapshots.last.summaryNote,
        contains('4.20% YoY'),
      );

      final relations = await dao.relationsFor('person-1');
      expect(relations, hasLength(1));
      expect(relations.single.relationType, EntityRelationType.impactedByNews);
      expect(relations.single.toEntityId, usaNews.id);

      final second = await repository.importCpi(
        countryCodes: ['USA', 'GBR'],
        startYear: 2024,
      );
      expect(second.observationCount, 3);
      expect(await repository.latestObservations(), hasLength(2));
      expect(await dao.searchEntities('', category: EntityCategory.economicNews),
          hasLength(2));
      expect(await dao.relationsFor('person-1'), hasLength(1));

      final settings = await repository.loadSettings();
      expect(settings.lastSyncAt, isNotNull);
      expect(settings.apiVersion, ImfApiVersion.v21);
      expect(settings.countryCodes, ['USA', 'GBR']);
      expect(await repository.shouldAutoRefresh(), isFalse);
    });

    test('persists SDMX 3.0 and records its exact source URL', () async {
      SharedPreferences.setMockInitialValues({});
      final database = await newDatabase();
      addTearDown(database.close);
      final dao = WealthDao(database);

      final requests = <Uri>[];
      final mock = MockClient((request) async {
        requests.add(request.url);
        expect(request.headers['Accept'], 'application/json');
        return http.Response(sampleV30DataMessage, 200);
      });
      final preferences = await SharedPreferences.getInstance();
      final repository = ImfRepository(
        database,
        client: ImfSdmxClient(client: mock),
        preferences: preferences,
      );
      await repository.saveSettings(
        const ImfSettings(
          countryCodes: ['USA'],
          autoRefresh: false,
          startYear: 2025,
          apiVersion: ImfApiVersion.v30,
        ),
      );

      final summary = await repository.importCpi();

      expect(summary.apiVersion, ImfApiVersion.v30);
      expect(summary.observationCount, 2);
      expect(requests, hasLength(1));
      expect(requests.single.pathSegments, contains('3.0'));
      expect(requests.single.pathSegments, contains('dataflow'));
      expect(requests.single.pathSegments, contains('5.0.0'));

      final latest = await repository.latestObservations();
      expect(latest, hasLength(1));
      expect(latest.single.value, closeTo(3.7, 0.0001));
      expect(latest.single.sourceUrl, contains('/3.0/data/dataflow/'));
      expect(latest.single.sourceUrl, requests.single.toString());

      final news = await dao.searchEntities(
        '',
        category: EntityCategory.economicNews,
      );
      expect(news, hasLength(1));
      expect(news.single.metadataJson, contains('"apiVersion":"3.0"'));

      final settings = await repository.loadSettings();
      expect(settings.apiVersion, ImfApiVersion.v30);
    });

    test('auto-refresh only triggers after the 24 hour interval', () async {
      SharedPreferences.setMockInitialValues({});
      final database = await newDatabase();
      addTearDown(database.close);
      final preferences = await SharedPreferences.getInstance();
      final repository = ImfRepository(database, preferences: preferences);

      await repository.saveSettings(
        const ImfSettings(
          countryCodes: ['USA'],
          autoRefresh: true,
          startYear: 2022,
          lastSyncAt: '2026-11-17T00:00:00Z',
        ),
      );
      expect(
        await repository.shouldAutoRefresh(
          DateTime.utc(2026, 11, 17, 12),
        ),
        isFalse,
      );
      expect(
        await repository.shouldAutoRefresh(
          DateTime.utc(2026, 11, 19),
        ),
        isTrue,
      );
    });
  });
}
