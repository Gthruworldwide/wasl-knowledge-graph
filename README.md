# Wasl (وصل)

Wasl is a standalone Flutter mobile app (`com.gthruworldwide.wasl.app`) and local-first knowledge graph. It has no connection to the legacy football app or its backend.

## Wealth data foundation

The version 6 SQLite database in `lib/data/wealth_database.dart` defines entities, weekly snapshots, income streams, relations, sources, a local cache of IMF CPI observations, a local cache of Financial Modeling Prep market context, and a `market_data_cache` of gold/silver quotes where every row carries a `provenance` label. Entities and relations retain source links; relations also support optional valid-time ranges. `WealthDao` provides typed access and recalculates a snapshot's week-over-week percentage against the immediately preceding ISO week. The importer writes a complete bundle in a single transaction.

The general connected-knowledge screen remains the app's primary view. Open the wealth pilot using the insights icon. It provides category filters, sourced wealth cards and profiles, history charts, income diversification, and clickable holdings. Users can add a sourced entity manually or paste a v2.0 JSON bundle; the fictional sample is clearly labeled and imported only on explicit selection.

`assets/seed/weekly_bundle_v2.json` is a fictional example bundle. Its values and relationships are illustrative only, not claims about real people or organizations. It is bundled but is not automatically imported.

`assets/sample_weekly_pack.json` is a richer fictional weekly pack with an athlete, an artist, a company, a linked luxury property, and an economic-news update. The empty wealth state and the wealth overflow menu both expose an **Import Sample Pack** action so the cards, history charts, income breakdown, and entity relations can be exercised immediately. The pack uses the optional `snapshots` array to import several weeks of history in one transaction; it also stays compatible with the original single `snapshot` object.

```dart
final db = WealthDatabase();
final summary = await WeeklyBundleImporter(db).importBundle(jsonText);
```

The importer accepts bundle version `2.0`; its source must be `JSON_IMPORT`. Re-importing the same bundle upserts its entities, snapshots, streams, and relations. It rejects duplicate snapshot weeks, entities that link to themselves, unsupported currency units (only `USD_M` and `USD_B`), and malformed `lastUpdatedWeek` values.

The add/edit sheet works without JSON: choose a category, enter the name and optional details, add income streams with annual values and portfolio-share percentages, and link existing property or company entities. New entities receive a `MANUAL` source. Editing an existing entity keeps its original source and only lets users change profile fields, income streams, and `OWNS_PROPERTY`/`OWNS_STAKE` links, so provenance cannot be overwritten. Open the editor from the add button or the pencil action on a wealth profile.

Each wealth profile also has an **Add weekly update** action. It records a net worth estimate, currency unit, and optional note for an ISO week without modifying earlier weeks, then recalculates week-over-week change. Existing weeks are rejected rather than silently overwritten. Profiles show the history chart with ISO week labels and one chronological feed that merges weekly notes with linked economic-news items and their source citations. When the newest week is note-only (no estimate), cards and profiles keep showing the most recent valued snapshot while the note still appears in the timeline.

## IMF CPI indicators (SDMX 2.1 and 3.0)

The **IMF Indicators** screen (globe icon on the knowledge and wealth home screens) imports annual CPI inflation by country from the IMF's public SDMX API. **SDMX 2.1 is the default**; the screen has an API-version selector for **SDMX 3.0**, and the choice is persisted in `SharedPreferences`. `ImfSdmxClient` builds the documented data, structure, availability, and (for 3.0) metadata URLs, then normalizes both JSON envelopes into one model. 3.0 uses `/data/dataflow/{agency}/{resource}/{version}/{key}` with an indexed `structures` array; 2.1 uses `/data/{flowRef}/{key}/{providerRef}`.

`ImfRepository` fetches the `IMF.STA,CPI` dataflow with key `COUNTRY.CPI._T.YOY_PCH_PA_PT.M` (3.0 pins dataflow version `5.0.0`), then writes everything to the device in one transaction:

- monthly observations are cached in `imf_observations` for offline browsing and trend sparklines;
- one note-only `ECONOMIC_NEWS` entity per country is created with the IMF source and the **exact generated request URL** for the selected API version;
- each observation becomes a weekly note, and entities whose nationality or metadata matches the country get an `IMPACTED_BY_NEWS` relation to that news node.

Re-importing upserts deterministic IDs, so no duplicate observations, notes, or links are created. Countries, start year, API version, and the optional auto-refresh setting are stored in `SharedPreferences`. Auto-refresh is **off by default**; when enabled it checks once per 24 hours when the indicators screen opens. There is no background service or account sync.

```dart
final repository = ImfRepository(db);
final summary = await repository.importCpi(
  countryCodes: ['USA', 'GBR'],
  apiVersion: ImfApiVersion.v30,
);
```

### FMP market context

The same screen can optionally show context from Financial Modeling Prep (FMP). **The API key is entered at runtime** through the **API key** button: it is stored only in this device's `SharedPreferences`, is never written to source, tests, or documentation, and is sent in an `apikey` HTTP header rather than in the URL. Saved source URLs contain no credentials, and error messages scrub the key before display. Use **Clear** to remove it.

FMP sync is **explicit only** (`Sync FMP`) — there is no background fetch and it is unrelated to the IMF auto-refresh. `FmpClient` calls the stable `/economic-indicators?name=CPI` endpoint and **one `/quote?symbol=...` request per symbol** (the batch-quote endpoint returns HTTP 402 on the free key). It covers the indices `^GSPC`, `^IXIC`, `^DJI` plus best-effort extended symbols (`GLD`, `SLV`, `SPY`, `QQQ`, `BTCUSD`, `ETHUSD`). An unavailable symbol becomes a sync warning and never discards the other quotes. `/stable/batch-quote`, `/stable/economic-calendar` (402) and `/stable/treasury-rates` (404) are documented as blocked and are never called. Rows are cached in `fmp_market_context` with `UNIQUE(kind, symbol, period)`, so re-syncing upserts instead of duplicating rows. Cached cards remain available offline.

```dart
await repository.saveFmpApiKey(keyEnteredByUser);
final summary = await repository.syncFmpContext();
final quotes = await repository.fmpContext();
```

### Yahoo gold and assets (key-free)

The same screen has a separate **Sync market** action for key-free Yahoo Finance quotes: `GC=F` (COMEX gold future), `GLD` (gold ETF) and `SLV` (silver ETF). `XAUUSD=X` is intentionally excluded because this endpoint does not return it. `MarketDataClient` builds credential-free chart URLs that are safe to persist as provenance; `MarketDataRepository` caches three labeled rows in `market_data_cache` (a `cached` row is the local result of an explicit `live` fetch). These quotes are shown with their source alongside the FMP ETF quotes rather than silently merged.

```dart
final market = MarketDataRepository(db);
final summary = await market.syncMarketData();
final rows = await market.latest();
```

## Development

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

The app uses platform SQLite through `sqflite`. `package:sqlite3` is only needed by the FFI test database, so `pubspec.yaml` configures its build hook to use the operating system SQLite (`winsqlite3` on Windows, `sqlite` on Android) instead of downloading prebuilt binaries. `android/gradle.properties` disables Kotlin incremental compilation and runs the compiler in-process, which avoids cross-drive cache failures when the project and pub cache are on different drives.

Both the general knowledge graph and wealth records are stored locally on the device. Network calls are limited to the explicit (or user-opted-in) IMF CPI import, the explicit key-gated FMP context sync and the explicit key-free Yahoo market sync described above; all three cache their results locally. Wasl does not add account synchronization or background feeds. AI explanations are local-only by default and consent-gated; see below. The UI does not independently verify user-provided source URLs or imported claims, and IMF/FMP/Yahoo figures are presented with their API source URL for the user to verify. See [WASL_API_COVERAGE.md](WASL_API_COVERAGE.md) for the full endpoint list, key handling and blocked endpoints.

## Scoped AI layer (local-first)

The **Grounded explanation** screen (robot icon) implements phases 1–3 of `WASL_FINANCIAL_AI_SPEC.md`:

- **Grounded retrieval** — every answer is assembled only from the local equation catalog, the deterministic `EquationEngine`, locally stored knowledge entities and cached IMF observations. Each claim is labeled `sourcedValue`, `computedResult`, `estimate`, `generatedExplanation` or `unavailable`; missing evidence yields «غير متاح» with a reason, never an invented number.
- **Strict tools** — typed read-only calls (`getEquationSpec`, `computeEquation`, `searchKnowledge`, `latestObservation`). There is no arbitrary SQL; a `writeDatabase` request is explicitly refused until a separate, non-AI UI confirms it.
- **Functional experts** — distinct instructions for the equation tutor, metric explainer and data quality reviewer. The coordinator itself never computes or invents a number or a fact; the engine remains the sole source of final answers.

A hosted model is **disabled by default**. An optional OpenAI-compatible transport (`POST /v1/chat/completions`) becomes available only after the user enters a base URL, model and key through **Model settings**. The key is device-local only and is sent solely in an `Authorization: Bearer` header — never in a URL, body, log or provenance — and is scrubbed from errors. Consent is session-scoped and in memory only; the user sees the exact allowlisted payload before approving, can cancel, and can revoke consent and clear session data. The payload contains only the expert name, the user's question and the grounded claim/citation projection — never user history, raw database rows or API keys. A sanitizer redacts credential-bearing fields and URL parameters, and a numeric output guard rejects any hosted text that introduces a number absent from the payload; hosted text is labeled "generated wording only" and never replaces a deterministic answer.

Privacy, cost, model/source licensing and the fine-tuning gate are recorded in [WASL_AI_REVIEW.md](WASL_AI_REVIEW.md). Those provider/owner decisions remain outstanding even though the transport is implemented. The repository is private and has no `LICENSE`; no open-source redistribution rights are granted.

## Local API (offline, no network)

`WaslLocalApi` (`lib/data/local_api.dart`) exposes the deterministic engines, grounded coordinator and read-only tools as a typed, in-process facade plus a JSON request/response envelope. It performs **no network** and never fetches — cached reads only. Use `describe()` for introspection; `writeDatabase` is always refused and there is no arbitrary SQL. See [WASL_LOCAL_API.md](WASL_LOCAL_API.md) for the full method and schema reference.

```dart
final api = WaslLocalApi(database: db);
final response = await api.call(
  LocalApiRequest(method: 'equation.compute', params: <String, Object?>{
    'id': 'wealth.net_worth',
    'inputs': <Object?>[],
  }),
);
```

## Local research lab (`finance_lab/`)

`finance_lab/` is a separate Python environment used for offline research and for validating market/gold/portfolio numbers before they inform the app. It is not shipped inside the Flutter app and contains no API keys (only placeholders in `.env.example`). See `finance_lab/README.md` for setup and outputs. CI for it lives at `.github/workflows/finance-lab-ci.yml` (GitHub Actions / Buildkite compatibility, push and PR only — no `schedule`).

For the scoped financial metrics, formulas, formula-training workflow, AI engine boundaries, privacy requirements, and licensing status, see [WASL_FINANCIAL_AI_SPEC.md](WASL_FINANCIAL_AI_SPEC.md).
