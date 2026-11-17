import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wasl_app/data/ai_models.dart';
import 'package:wasl_app/data/equation_models.dart';
import 'package:wasl_app/data/local_api.dart';
import 'package:wasl_app/data/wealth_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  final netWorthInputs = <Map<String, Object?>>[
    <String, Object?>{
      'value': 100000,
      'unit': 'currency',
      'source_kind': 'synthetic',
    },
    <String, Object?>{
      'value': 25000,
      'unit': 'currency',
      'source_kind': 'synthetic',
    },
  ];

  Future<WaslLocalApi> newApi() async {
    SharedPreferences.setMockInitialValues({});
    final database = WealthDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    await database.database;
    return WaslLocalApi(database: database);
  }

  test('describe exposes methods, tools and provenance labels with no network',
      () async {
    final api = await newApi();
    addTearDown(api.close);
    final description = api.describe();
    expect(description['transport'], 'local_in_process');
    expect(description['network'], 'none');
    expect(
      description['methods'],
      containsAll([
        'equation.list',
        'equation.compute',
        'ai.explain',
        'market.latest',
        'tools.invoke',
      ]),
    );
    expect(description['provenance_labels'], ['live', 'cached', 'synthetic', 'manual']);
    final tools = description['tools'] as List<Object?>;
    expect(tools, hasLength(AiToolName.values.length));
    expect(
      tools.any(
        (item) =>
            (item as Map<String, Object?>)['name'] == 'writeDatabase' &&
            item['read_only'] == false,
      ),
      isTrue,
    );
  });

  test('typed surface lists, computes and grades from the deterministic engine',
      () async {
    final api = await newApi();
    addTearDown(api.close);
    expect(api.listEquations(), hasLength(18));
    expect(api.getEquation('wealth.net_worth').version, isNotEmpty);

    final inputs = [
      const MetricInput(value: 100000, unit: EquationUnit.currency, sourceKind: EquationSourceKind.synthetic),
      const MetricInput(value: 25000, unit: EquationUnit.currency, sourceKind: EquationSourceKind.synthetic),
    ];
    final result = api.compute(id: 'wealth.net_worth', inputs: inputs);
    expect(result.defined, isTrue);
    expect(result.value, closeTo(75000, 0.0001));
    final answer = api.grade(
      id: 'wealth.net_worth',
      inputs: inputs,
      learnerValue: 75000,
    );
    expect(answer.correct, isTrue);
  });

  test('JSON envelope computes, explains and refuses a database write', () async {
    final api = await newApi();
    addTearDown(api.close);

    final spec = await api.call(
      const LocalApiRequest(method: 'equation.spec', params: <String, Object?>{'id': 'wealth.net_worth'}),
    );
    expect(spec.ok, isTrue);
    expect(spec.apiVersion, WaslLocalApi.version);
    expect((spec.data as Map<String, Object?>)['id'], 'wealth.net_worth');

    final computed = await api.call(
      LocalApiRequest(
        method: 'equation.compute',
        params: <String, Object?>{
          'id': 'wealth.net_worth',
          'inputs': netWorthInputs,
        },
      ),
    );
    expect(computed.ok, isTrue);
    expect((computed.data as Map<String, Object?>)['value'], closeTo(75000, 0.0001));

    final explained = await api.call(
      LocalApiRequest(
        method: 'ai.explain',
        params: <String, Object?>{
          'expert': 'equationTutor',
          'equation_id': 'wealth.net_worth',
          'inputs': netWorthInputs,
        },
      ),
    );
    expect(explained.ok, isTrue);
    final claims = (explained.data as Map<String, Object?>)['claims'] as List<Object?>;
    expect(claims.map((claim) => (claim as Map<String, Object?>)['kind']), contains('computedResult'));

    final write = await api.call(
      const LocalApiRequest(
        method: 'tools.invoke',
        params: <String, Object?>{
          'tool': 'writeDatabase',
          'args': <String, Object?>{},
        },
      ),
    );
    expect((write.data as Map<String, Object?>)['ok'], isFalse);

    final unknown = await api.call(const LocalApiRequest(method: 'nope'));
    expect(unknown.ok, isFalse);
    expect(unknown.error, contains('Unknown local API method'));
  });

  test('JSON envelope reads empty local caches without any fetch', () async {
    final api = await newApi();
    addTearDown(api.close);
    for (final method in ['imf.latest', 'fmp.context', 'market.latest', 'knowledge.search']) {
      final response = await api.call(
        LocalApiRequest(method: method, params: <String, Object?>{'query': ''}),
      );
      expect(response.ok, isTrue, reason: '$method: ${response.error}');
      expect(response.data, isEmpty, reason: method);
    }
    final market = await api.call(
      const LocalApiRequest(
        method: 'market.latest',
        params: <String, Object?>{'asset': 'GOLD_FUTURE'},
      ),
    );
    expect(market.ok, isTrue);
    expect(market.data, isEmpty);
  });
}
