import 'ai_grounding.dart';
import 'ai_models.dart';
import 'ai_tools.dart';
import 'equation_catalog.dart';
import 'equation_engine.dart';
import 'equation_models.dart';
import 'fmp_context.dart';
import 'imf_observation.dart';
import 'imf_repository.dart';
import 'knowledge_store.dart';
import 'market_data_client.dart';
import 'market_data_repository.dart';
import 'wealth_database.dart';

/// A JSON-friendly request envelope for the local, offline API.
class LocalApiRequest {
  const LocalApiRequest({required this.method, this.params = const <String, Object?>{}});

  final String method;
  final Map<String, Object?> params;

  factory LocalApiRequest.fromJson(Map<String, Object?> json) => LocalApiRequest(
    method: json['method']! as String,
    params: json['params'] is Map
        ? Map<String, Object?>.from(json['params'] as Map)
        : const <String, Object?>{},
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'method': method,
    'params': params,
  };
}

/// A uniform response envelope. [error] is populated instead of throwing so
/// callers can treat the facade as a stable API boundary.
class LocalApiResponse {
  const LocalApiResponse._({
    required this.ok,
    this.data,
    this.error,
    required this.apiVersion,
  });

  final bool ok;
  final Object? data;
  final String? error;
  final String apiVersion;

  factory LocalApiResponse.success(Object? data, {required String apiVersion}) =>
      LocalApiResponse._(ok: true, data: data, apiVersion: apiVersion);

  factory LocalApiResponse.failure(String error, {required String apiVersion}) =>
      LocalApiResponse._(ok: false, error: error, apiVersion: apiVersion);

  Map<String, Object?> toJson() => <String, Object?>{
    'ok': ok,
    if (ok) 'data': data,
    if (!ok) 'error': error,
    'api_version': apiVersion,
  };
}

/// Typed, local-only facade over Wasl's deterministic engines and read-only
/// tools. No method performs a network fetch; explicit sync remains in the
/// repository layer and the UI.
class WaslLocalApi {
  WaslLocalApi({
    WealthDatabase? database,
    ImfRepository? imfRepository,
    MarketDataRepository? marketRepository,
    KnowledgeStore? knowledgeStore,
  })  : _ownsDatabase = database == null &&
            imfRepository == null &&
            marketRepository == null {
    final db = database ?? (imfRepository == null || marketRepository == null
        ? WealthDatabase()
        : null);
    _database = db;
    _imfRepository = imfRepository ?? (db == null ? null : ImfRepository(db));
    _marketRepository =
        marketRepository ?? (db == null ? null : MarketDataRepository(db));
    _knowledgeStore = knowledgeStore ?? KnowledgeStore.instance;
  }

  static const String version = '1.0.0';
  WealthDatabase? _database;
  final bool _ownsDatabase;
  ImfRepository? _imfRepository;
  MarketDataRepository? _marketRepository;
  late final KnowledgeStore _knowledgeStore;
  final AiToolRegistry _tools = const AiToolRegistry();
  final AiGroundingEngine _grounding = const AiGroundingEngine();

  Future<void> close() async {
    if (_ownsDatabase) await _database?.close();
  }

  // --- typed surface -------------------------------------------------------

  List<EquationSpec> listEquations() => List<EquationSpec>.of(equationCatalog);

  EquationSpec getEquation(String id) => equationSpecById(id);

  MetricResult compute({
    required String id,
    required List<MetricInput> inputs,
    DateTime? start,
    DateTime? end,
  }) => EquationEngine.computeById(id, inputs, start: start, end: end);

  GradedAnswer grade({
    required String id,
    required List<MetricInput> inputs,
    required double learnerValue,
    DateTime? start,
    DateTime? end,
  }) => EquationEngine.grade(
    id: id,
    inputs: inputs,
    learnerValue: learnerValue,
    start: start,
    end: end,
  );

  GroundedResponse explain({
    required AiExpertKind expert,
    required String equationId,
    required List<MetricInput> inputs,
    DateTime? start,
    DateTime? end,
  }) => switch (expert) {
    AiExpertKind.equationTutor => _grounding.explainEquation(
      equationId: equationId,
      inputs: inputs,
      start: start,
      end: end,
    ),
    AiExpertKind.metricExplainer => _grounding.explainMetric(
      equationId: equationId,
      inputs: inputs,
      start: start,
      end: end,
    ),
    AiExpertKind.dataQualityReviewer => _grounding.reviewDataQuality(inputs: inputs),
  };

  AiToolResult invoke(AiToolName tool, Map<String, Object?> args) =>
      _tools.call(tool, args);

  Future<AiToolResult> invokeAsync(
    AiToolName tool,
    Map<String, Object?> args,
  ) => _tools.callAsync(
    tool,
    args,
    knowledgeStore: _knowledgeStore,
    imfRepository: _imfRepository,
  );

  Future<List<KnowledgeEntity>> searchKnowledge(String query) =>
      _knowledgeStore.search(query);

  Future<List<ImfObservationRow>> latestObservations() =>
      _requireImf().latestObservations();

  Future<List<FmpContextRow>> fmpContext({FmpContextKind? kind}) =>
      _requireImf().fmpContext(kind: kind);

  Future<List<MarketDataRow>> marketData({MarketAssetKind? asset}) =>
      _requireMarket().latest(asset: asset);

  ImfRepository _requireImf() {
    final repository = _imfRepository;
    if (repository == null) throw StateError('No IMF repository is available.');
    return repository;
  }

  MarketDataRepository _requireMarket() {
    final repository = _marketRepository;
    if (repository == null) throw StateError('No market repository is available.');
    return repository;
  }

  // --- introspection -------------------------------------------------------

  Map<String, Object?> describe() => <String, Object?>{
    'api_version': version,
    'transport': 'local_in_process',
    'network': 'none',
    'methods': <Object?>[
      'equation.list',
      'equation.spec',
      'equation.compute',
      'equation.grade',
      'ai.explain',
      'knowledge.search',
      'imf.latest',
      'fmp.context',
      'market.latest',
      'tools.describe',
      'tools.invoke',
    ],
    'tools': <Object?>[
      for (final tool in AiToolName.values)
        <String, Object?>{
          'name': tool.name,
          'label_en': tool.label(false),
          'read_only': _tools.isAllowed(tool),
        },
    ],
    'provenance_labels': <Object?>['live', 'cached', 'synthetic', 'manual'],
  };

  // --- JSON envelope -------------------------------------------------------

  Future<LocalApiResponse> call(LocalApiRequest request) async {
    try {
      final data = await _dispatch(request.method, request.params);
      return LocalApiResponse.success(data, apiVersion: version);
    } on Object catch (error) {
      return LocalApiResponse.failure(error.toString(), apiVersion: version);
    }
  }

  Future<Object?> _dispatch(String method, Map<String, Object?> params) async {
    switch (method) {
      case 'equation.list':
        return [for (final spec in equationCatalog) _specJson(spec)];
      case 'equation.spec':
        return _specJson(getEquation(_string(params, 'id')));
      case 'equation.compute':
        final result = compute(
          id: _string(params, 'id'),
          inputs: _inputs(params['inputs']),
          start: _date(params['start']),
          end: _date(params['end']),
        );
        return _resultJson(result);
      case 'equation.grade':
        final answer = grade(
          id: _string(params, 'id'),
          inputs: _inputs(params['inputs']),
          learnerValue: _number(params['learner_value']),
          start: _date(params['start']),
          end: _date(params['end']),
        );
        return <String, Object?>{
          'reference': answer.reference,
          'learner': answer.learner,
          'tolerance': answer.tolerance,
          'correct': answer.correct,
          'steps': answer.steps,
          'note': answer.note,
        };
      case 'ai.explain':
        final response = explain(
          expert: _enum(AiExpertKind.values, params['expert'], 'equationTutor'),
          equationId: _string(params, 'equation_id'),
          inputs: _inputs(params['inputs']),
          start: _date(params['start']),
          end: _date(params['end']),
        );
        return <String, Object?>{
          'expert': response.expert.name,
          'has_evidence': response.hasEvidence,
          'claims': [
            for (final claim in response.claims)
              <String, Object?>{
                'kind': claim.kind.wireName,
                'text_ar': claim.textAr,
                'text_en': claim.textEn,
                'equation_id': claim.equationId,
                'provenance': claim.provenance,
              },
          ],
        };
      case 'knowledge.search':
        final query = params['query'] is String ? params['query'] as String : '';
        final entities = await searchKnowledge(query);
        return [for (final entity in entities) entity.toJson()];
      case 'imf.latest':
        final rows = await latestObservations();
        return [for (final row in rows) row.toRow()];
      case 'fmp.context':
        final kind = params['kind'] == null
            ? null
            : _fmpKind(params['kind'] as String);
        final rows = await fmpContext(kind: kind);
        return [for (final row in rows) row.toRow()];
      case 'market.latest':
        final asset = params['asset'] == null
            ? null
            : _marketAsset(params['asset'] as String);
        final rows = await marketData(asset: asset);
        return [for (final row in rows) row.toRow()];
      case 'tools.describe':
        return describe();
      case 'tools.invoke':
        final tool = _enum(AiToolName.values, params['tool'], AiToolName.getEquationSpec.name);
        final args = params['args'] is Map
            ? Map<String, Object?>.from(params['args'] as Map)
            : <String, Object?>{};
        final result = await invokeAsync(tool, args);
        return <String, Object?>{
          'ok': result.ok,
          'reason': result.reason,
          'citations': [for (final citation in result.citations) citation.toJson()],
        };
      default:
        throw ArgumentError('Unknown local API method: $method');
    }
  }

  // --- serialization helpers ----------------------------------------------

  Map<String, Object?> _specJson(EquationSpec spec) => <String, Object?>{
    'id': spec.id,
    'name_ar': spec.nameAr,
    'name_en': spec.nameEn,
    'domain': spec.domain,
    'formula': spec.formula,
    'symbols': spec.symbols,
    'inputs': [
      for (final input in spec.inputs)
        <String, Object?>{
          'name': input.name,
          'unit': input.unit.wireName,
          'source': input.source,
          'frequency': input.frequency,
        },
    ],
    'unit': spec.unit.wireName,
    'currency_policy': spec.currencyPolicy,
    'validity': spec.validity,
    'edge_cases': spec.edgeCases,
    'worked_example': spec.workedExample,
    'expected_output': spec.expectedOutput,
    'tolerance': spec.tolerance,
    'reference': spec.reference,
    'version': spec.version,
  };

  Map<String, Object?> _resultJson(MetricResult result) => <String, Object?>{
    'id': result.id,
    'value': result.value,
    'unit': result.unit.wireName,
    'currency': result.currency,
    'period': result.period?.label,
    'defined': result.defined,
    'reason': result.reason,
    'qualifier': result.qualifier,
    'source_kind': result.sourceKind.wireName,
    'display': result.display,
  };

  List<MetricInput> _inputs(Object? raw) {
    if (raw is! List) throw ArgumentError('inputs must be a list.');
    return [
      for (final item in raw)
        if (item is Map) _input(item),
    ];
  }

  MetricInput _input(Map<dynamic, dynamic> item) => MetricInput(
    value: item['value'] is num ? (item['value'] as num).toDouble() : null,
    unit: _enum(EquationUnit.values, item['unit'], EquationUnit.currency.name),
    currency: item['currency'] as String?,
    period: item['period'] == null
        ? null
        : EquationPeriod(
            label: '${item['period']}',
            start: _date(item['period_start']),
          ),
    sourceKind: _enum(
      EquationSourceKind.values,
      item['source_kind'],
      EquationSourceKind.manual.name,
    ),
    source: item['source'] as String?,
    estimated: item['estimated'] == true,
  );

  String _string(Map<String, Object?> params, String key) {
    final value = params[key];
    if (value is! String || value.isEmpty) {
      throw ArgumentError('A non-empty "$key" is required.');
    }
    return value;
  }

  double _number(Object? value) {
    if (value is! num) throw ArgumentError('A numeric value is required.');
    return value.toDouble();
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  FmpContextKind _fmpKind(String raw) {
    try {
      return FmpContextKind.parse(raw);
    } on FormatException {
      return _enum(FmpContextKind.values, raw, FmpContextKind.cpi.name);
    }
  }

  MarketAssetKind _marketAsset(String raw) {
    try {
      return MarketAssetKind.parse(raw);
    } on FormatException {
      return _enum(MarketAssetKind.values, raw, MarketAssetKind.goldFuture.name);
    }
  }

  T _enum<T extends Enum>(List<T> values, Object? raw, String fallback) {
    final name = raw is String && raw.isNotEmpty ? raw : fallback;
    return values.firstWhere(
      (item) => item.name == name,
      orElse: () => throw ArgumentError('Invalid enum value: $name'),
    );
  }
}
