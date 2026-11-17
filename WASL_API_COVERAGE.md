# Wasl API coverage

Wasl is local-first. Every external call below is **explicit** (a user taps a sync
button or approves a request). Nothing syncs in the background, and there is no
account service. Cached results stay on the device with their source URL and
retrieval time.

## 1. IMF SDMX (CPI)

| Item | Value |
|---|---|
| Endpoint | `https://api.imf.org/external/datamapper/api/v1/...` (SDMX 2.1) and the SDMX 3.0 CSV/JSON variant |
| Auth | None |
| Selection | `2.1` default, `3.0` selectable in the UI |
| Trigger | **Sync now** on the IMF Indicators screen; optional auto-refresh only when the screen opens, at most once per 24 h, off by default |
| Cache | `imf_observations` (SQLite) |
| Provenance | The exact, key-free request URL is stored as `source_url` with `fetched_at` |
| Labels | Every observation is a sourced value with period, unit and frequency |

## 2. Financial Modeling Prep (FMP) — market context

| Item | Value |
|---|---|
| Base | `https://financialmodelingprep.com/stable` |
| Auth | Runtime-entered key, sent **only** in the `apikey` request header |
| Key storage | On-device preferences only; never in source, tests, docs, logs, URLs or provenance |
| Trigger | **Sync FMP** on the IMF Indicators screen |
| Cache | `fmp_market_context` (SQLite v6) |

### Working endpoints on the free key

| Endpoint | Use | Notes |
|---|---|---|
| `GET /stable/economic-indicators?name=CPI` | Latest CPI point | One row kept (newest `date`). Example observed latest: `2026-10-01`, value `337.476`. |
| `GET /stable/quote?symbol=^GSPC` | S&P 500 | Single-symbol only. |
| `GET /stable/quote?symbol=^IXIC` | NASDAQ Composite | Single-symbol only. |
| `GET /stable/quote?symbol=^DJI` | Dow Jones | Single-symbol only. |
| `GET /stable/quote?symbol=<extended>` | Extra assets/crypto | Best-effort symbols: `^RUT`, `^VIX`, `GLD`, `SLV`, `SPY`, `QQQ`, `BTCUSD`, `ETHUSD`. An unavailable symbol becomes a sync warning; it never discards the other quotes. |

Every quote is its **own** request; there is no batch call. Request URLs are key-free, so they are safe to persist as provenance.

### Blocked / unavailable on the free key (recorded, not called)

| Endpoint | Observed result | Reason it is not used |
|---|---|---|
| `GET /stable/batch-quote` | HTTP 402 | Paid tier; single-symbol `/stable/quote` used instead. |
| `GET /stable/economic-calendar` | HTTP 402 | Paid tier. |
| `GET /stable/treasury-rates` | HTTP 404 | Endpoint not available on the current key/plan. |

The client never calls these endpoints, so a free key never produces a paid-tier error loop.

## 3. Yahoo Finance — gold and assets

| Item | Value |
|---|---|
| Base | `https://query1.finance.yahoo.com/v8/finance/chart/<symbol>?interval=1d&range=5d` |
| Auth | None (no key to leak) |
| Symbols | `GC=F` (COMEX gold future), `GLD` (gold ETF), `SLV` (silver ETF) |
| Excluded | `XAUUSD=X` — not returned by this endpoint in this environment |
| Trigger | **Sync market** on the IMF Indicators screen |
| Cache | `market_data_cache` (SQLite v6) |
| Provenance | Key-free chart URL + `fetched_at`; each row stores a `provenance` label (`cached` at rest, originating from a `live` fetch) |

These quotes are a separate, labeled source from FMP's ETF quotes; showing both with provenance is intentional.

## 4. Hosted AI provider (optional, off by default)

| Item | Value |
|---|---|
| Transport | `HttpHostedAiTransport`, OpenAI-compatible `POST /v1/chat/completions` |
| Base URL / model / key | Entered at runtime in **Model settings**; saved on-device only |
| Key handling | Sent **only** as `Authorization: Bearer …`; never in the URL, body, logs, docs or provenance; scrubbed from errors |
| Gate | Disabled until settings are configured; a payload preview and explicit consent are required for **every** request; cancel and session-data removal always available |
| Payload | Expert name, user question, and allowlisted grounded claims/citations only. Sanitizer strips credential-like fields and URL parameters. |
| Output guard | `HostedAiTextGuard` rejects any number absent from the payload; generated text is wording only and is never shown as a deterministic answer |
| Review | [WASL_AI_REVIEW.md](WASL_AI_REVIEW.md) |

## 5. Local API (no network)

`WaslLocalApi` and [WASL_LOCAL_API.md](WASL_LOCAL_API.md) expose the deterministic
engines, grounded coordinator and read-only tools as a typed, in-process facade.
It never fetches: explicit sync stays in the repositories above.
