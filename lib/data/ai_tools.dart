import 'ai_models.dart';
import 'equation_catalog.dart';
import 'equation_engine.dart';
import 'equation_models.dart';
import 'imf_repository.dart';
import 'knowledge_store.dart';

/// Read-only, strictly typed tool surface for the AI coordinator.
///
/// There is no arbitrary SQL and no unconfirmed write path. The only write
/// tool name exists so callers get an explicit refusal instead of silence.
class AiToolRegistry {
  const AiToolRegistry();

  static const _blockedWriteReason =
      'write_requires_explicit_user_confirmation';

  bool isAllowed(AiToolName tool) => tool != AiToolName.writeDatabase;

  AiToolResult call(AiToolName tool, Map<String, Object?> args) {
    if (!isAllowed(tool)) {
      return AiToolResult.failure(_blockedWriteReason);
    }
    switch (tool) {
      case AiToolName.getEquationSpec:
        return _getEquationSpec(args);
      case AiToolName.computeEquation:
        return _computeEquation(args);
      case AiToolName.writeDatabase:
        return AiToolResult.failure(_blockedWriteReason);
      default:
        return AiToolResult.failure('tool_requires_async_dispatch');
    }
  }

  Future<AiToolResult> callAsync(
    AiToolName tool,
    Map<String, Object?> args, {
    KnowledgeStore? knowledgeStore,
    ImfRepository? imfRepository,
  }) async {
    if (!isAllowed(tool)) {
      return AiToolResult.failure(_blockedWriteReason);
    }
    switch (tool) {
      case AiToolName.searchKnowledge:
        final store = knowledgeStore;
        if (store == null) return AiToolResult.failure('missing_knowledge_store');
        final query = args['query'];
        if (query is! String || query.trim().isEmpty) {
          return AiToolResult.failure('invalid_query');
        }
        final entities = await store.search(query.trim());
        return AiToolResult.success(
          entities,
          citations: [
            for (final entity in entities)
              Citation(
                label: entity.name,
                uri: entity.sourceUri,
                retrievedAt: entity.createdAt,
              ),
          ],
        );
      case AiToolName.latestObservation:
        final repository = imfRepository;
        if (repository == null) {
          return AiToolResult.failure('missing_imf_repository');
        }
        final rows = await repository.latestObservations();
        return AiToolResult.success(
          rows,
          citations: [
            for (final row in rows)
              Citation(
                label: '${row.countryName} ${row.period}',
                uri: row.sourceUrl,
                retrievedAt: row.fetchedAt,
              ),
          ],
        );
      default:
        return call(tool, args);
    }
  }

  AiToolResult _getEquationSpec(Map<String, Object?> args) {
    final id = args['id'];
    if (id is! String) return AiToolResult.failure('invalid_equation_id');
    try {
      final spec = equationSpecById(id);
      return AiToolResult.success(
        spec,
        citations: [
          Citation(label: 'catalog:$id@${spec.version}', uri: 'catalog://wasl/equations/$id'),
        ],
      );
    } on ArgumentError {
      return AiToolResult.failure('unknown_equation_id');
    }
  }

  AiToolResult _computeEquation(Map<String, Object?> args) {
    final id = args['id'];
    if (id is! String) return AiToolResult.failure('invalid_equation_id');
    final rawInputs = args['inputs'];
    if (rawInputs is! List<MetricInput>) {
      return AiToolResult.failure('invalid_typed_inputs');
    }
    final start = args['start'];
    final end = args['end'];
    if (start != null && start is! DateTime) {
      return AiToolResult.failure('invalid_start_date');
    }
    if (end != null && end is! DateTime) {
      return AiToolResult.failure('invalid_end_date');
    }
    try {
      final spec = equationSpecById(id);
      final result = EquationEngine.computeById(
        id,
        rawInputs,
        start: start as DateTime?,
        end: end as DateTime?,
      );
      return AiToolResult.success(
        result,
        citations: [
          Citation(label: 'catalog:$id@${spec.version}', uri: 'catalog://wasl/equations/$id'),
        ],
      );
    } on ArgumentError {
      return AiToolResult.failure('unknown_equation_id');
    }
  }
}
