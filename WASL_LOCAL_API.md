# Wasl local API (`WaslLocalApi`)

`WaslLocalApi` is an **in-process, local-only** facade over Wasl's deterministic
engines, grounded coordinator and read-only tools. It performs **no network I/O**:
explicit fetches stay in the repository layer (see
[WASL_API_COVERAGE.md](WASL_API_COVERAGE.md)). It has two surfaces:

1. a **typed Dart API** for in-app callers, and
2. a **JSON request/response envelope** for a stable, scriptable boundary.

Both surfaces share the same version, `WaslLocalApi.version` (`1.0.0`).

## Construction

```dart
final api = WaslLocalApi();          // owns its own WealthDatabase
// or inject existing singletons so the API reuses them:
final api = WaslLocalApi(
  database: db,
  imfRepository: imfRepo,
  marketRepository: marketRepo,
  knowledgeStore: KnowledgeStore.instance,
);
// ...
await api.close();                   // closes only a database the API created
```

No constructor argument triggers a fetch. Read methods return whatever is
already cached on the device; an empty cache yields an empty list.

## Typed surface

| Method | Returns | Network |
|---|---|---|
| `listEquations()` | `List<EquationSpec>` | none |
| `getEquation(String id)` | `EquationSpec` | none |
| `compute(id:, inputs:, start?, end?)` | `MetricResult` | none |
| `grade(id:, inputs:, learnerValue:, start?, end?)` | `GradedAnswer` | none |
| `explain(expert:, equationId:, inputs:, start?, end?)` | `GroundedResponse` | none |
| `invoke(AiToolName, args)` | `AiToolResult` (sync tools) | none |
| `invokeAsync(AiToolName, args)` | `Future<AiToolResult>` (all tools) | none |
| `searchKnowledge(String query)` | `Future<List<KnowledgeEntity>>` | none |
| `latestObservations()` | `Future<List<ImfObservationRow>>` | none (cached) |
| `fmpContext({kind})` | `Future<List<FmpContextRow>>` | none (cached) |
| `marketData({asset})` | `Future<List<MarketDataRow>>` | none (cached) |
| `describe()` | `Map<String, Object?>` | none |

`invoke`/`invokeAsync` route through `AiToolRegistry`. `writeDatabase` is always
refused with `write_requires_explicit_user_confirmation`; there is no arbitrary
SQL path.

Example:

```dart
final inputs = [
  MetricInput(value: 100000, unit: EquationUnit.currency,
      sourceKind: EquationSourceKind.synthetic),
  MetricInput(value: 25000, unit: EquationUnit.currency,
      sourceKind: EquationSourceKind.synthetic),
];
final result = api.compute(id: 'wealth.net_worth', inputs: inputs);
// result.value == 75000, result.sourceKind reflects the inputs
```

## JSON envelope

```dart
final response = await api.call(
  const LocalApiRequest(
    method: 'equation.compute',
    params: <String, Object?>{
      'id': 'wealth.net_worth',
      'inputs': <Object?>[
        <String, Object?>{'value': 100000, 'unit': 'currency',
            'source_kind': 'synthetic'},
        <String, Object?>{'value': 25000, 'unit': 'currency',
            'source_kind': 'synthetic'},
      ],
    },
  ),
);
// response.toJson() =>
//   {'ok': true, 'data': {...}, 'api_version': '1.0.0'}
```

Request — `LocalApiRequest`:

```json
{ "method": "equation.compute", "params": { "id": "wealth.net_worth", "inputs": [] } }
```

Response — `LocalApiResponse`:

```json
{ "ok": true, "data": { }, "api_version": "1.0.0" }
{ "ok": false, "error": "Unknown local API method: nope", "api_version": "1.0.0" }
```

Errors are returned in the envelope rather than thrown, so the facade is a
stable boundary. `error` is only present when `ok` is `false`.

## Methods and parameters

All `params` keys are optional unless noted. Enums accept either their `name`
(`cpi`, `goldFuture`, `equationTutor`) or their database value where one exists
(`CPI`, `GOLD_FUTURE`).

| Method | Params | Result (`data`) |
|---|---|---|
| `equation.list` | — | array of equation specs |
| `equation.spec` | `id` (required) | one equation spec |
| `equation.compute` | `id` (required), `inputs`, `start`, `end` | `MetricResult` object |
| `equation.grade` | `id` (required), `inputs`, `learner_value`, `start`, `end` | `GradedAnswer` object |
| `ai.explain` | `expert`, `equation_id`, `inputs`, `start`, `end` | grounded response object |
| `knowledge.search` | `query` (defaults to `''`) | array of knowledge entities |
| `imf.latest` | — | array of cached IMF rows |
| `fmp.context` | `kind` | array of cached FMP rows |
| `market.latest` | `asset` | array of cached market rows |
| `tools.describe` | — | the full `describe()` object |
| `tools.invoke` | `tool`, `args` | `{ ok, reason?, citations[] }` |

### Result shapes

`equation.spec` / `equation.list` item:

```json
{
  "id": "wealth.net_worth", "name_ar": "…", "name_en": "…",
  "domain": "…", "formula": "…", "symbols": { },
  "inputs": [ { "name": "…", "unit": "currency", "source": "…",
                "frequency": "…" } ],
  "unit": "currency", "currency_policy": "…", "validity": "…",
  "edge_cases": "…", "worked_example": "…", "expected_output": "…",
  "tolerance": 0.0, "reference": "…", "version": "…"
}
```

`equation.compute` (`MetricResult`):

```json
{
  "id": "wealth.net_worth", "value": 75000, "unit": "currency",
  "currency": null, "period": "…", "defined": true,
  "reason": null, "qualifier": null,
  "source_kind": "synthetic", "display": "…"
}
```

`equation.grade` (`GradedAnswer`): `reference`, `learner`, `tolerance`,
`correct`, `steps`, `note`.

`ai.explain`:

```json
{
  "expert": "equationTutor", "has_evidence": true,
  "claims": [
    { "kind": "computedResult", "text_ar": "…", "text_en": "…",
      "equation_id": "wealth.net_worth", "provenance": "synthetic" }
  ]
}
```

`imf.latest`, `fmp.context` and `market.latest` return the database row maps
(`toRow()`), which include `source_url`, `fetched_at`, period and unit/value —
never an API key. `market.latest` rows also carry the `provenance` label
(`live`, `cached`, `synthetic`, `manual`).

### Input shape (`inputs[]`)

```json
{
  "value": 100000, "unit": "currency", "currency": "USD",
  "period": "2026-Q4", "period_start": "2026-10-01T00:00:00Z",
  "source_kind": "synthetic", "source": "demo", "estimated": false
}
```

`source_kind` is one of `live`, `cached`, `synthetic`, `manual`. Synthetic or
estimated inputs are surfaced as `estimate` claims and are never presented as
real market data.

## Introspection

`api.describe()` (also returned by `tools.describe`) reports the API version,
the `transport: local_in_process` / `network: none` guarantee, the full method list, every
tool with a `read_only` flag, and the four provenance labels. Use it to discover
the surface at runtime instead of hardcoding method names.

## Invariants

- No network calls, no account sync, no background service.
- No API keys in requests, responses, errors or provenance.
- `writeDatabase` is always refused; no arbitrary SQL.
- Every financial value keeps its provenance label; synthetic values are never
  shown as real or used in reports.
- The deterministic `EquationEngine` is the sole source of final numbers; the
  optional hosted AI layer may only rephrase grounded text (see
  [WASL_AI_REVIEW.md](WASL_AI_REVIEW.md)).
