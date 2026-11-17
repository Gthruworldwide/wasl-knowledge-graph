# Wasl AI — privacy, cost and license review gate

Status: **hosted transport implemented but owner-gated**. The app always ships
with a local-only, deterministic explanation coordinator. An optional hosted
transport exists but is **off by default**: it stays disabled until the user
enters a provider at runtime, and each request still requires an explicit
payload review and consent. This document does **not** grant approval to use a
specific provider; the owner decisions in the gates below remain outstanding.

The Wasl repository is **private** and has **no `LICENSE` file**. The mere
existence of `WASL_FINANCIAL_AI_SPEC.md` or this document grants no open-source
redistribution rights. Choosing a license remains a separate decision by the
project owner before making the repository public or distributing the app.

## What is implemented now

- Grounded retrieval: claims are built only from the local equation catalog,
  the deterministic `EquationEngine`, locally stored knowledge entities and
  cached IMF observations. Every claim is labeled as one of:
  `sourcedValue`, `computedResult`, `estimate`, `generatedExplanation`,
  `unavailable`. Missing evidence produces **«غير متاح»** with a reason, never
  an invented number.
- Strict tools: `getEquationSpec`, `computeEquation`, `searchKnowledge`,
  `latestObservation`. Inputs are typed; there is no arbitrary SQL. A
  `writeDatabase` request is explicitly refused until the user confirms a
  write through a separate, non-AI UI.
- Functional experts: separate configurations and prohibitions for the
  equation tutor, metric explainer and data quality reviewer. The coordinator
  never computes or invents a number or a fact.
- Consent: session-scoped and in memory only. Nothing is persisted. The user
  sees the exact allowlisted payload before approving, can cancel, and can
  revoke consent and clear session data at any time.
- Hosted transport (`HttpHostedAiTransport`, OpenAI-compatible
  `POST /v1/chat/completions`): disabled until the user supplies a base URL,
  model and key through **Model settings**. The key is device-local only, sent
  **only** in an `Authorization: Bearer …` header, never in a URL, body, log or
  provenance, and scrubbed from error messages. Request URLs and error objects
  are key-free.
- Defense in depth: `AiPayloadSanitizer` strips credential-like keys and
  credential-bearing URL parameters from the allowlisted payload before any
  transfer. `AiPayload` itself has no key field.
- Numeric output guard: `HostedAiTextGuard` rejects any hosted text containing a
  number not already present in the payload (with Arabic-Indic/comma-digit
  normalization). Rejected text is never stored or displayed. Hosted text is
  labeled "generated wording only"; final numbers always come from the deterministic
  engine.

## Exact hosted payload allowlist

A hosted request may receive only:

```
expert        enum name (equationTutor | metricExplainer | dataQualityReviewer)
question      free text entered by the user for this request
claims[]      kind, text_ar, text_en, equation_id?, provenance?, citations[]
citations[]   label, uri, retrieved_at?
```

Excluded, always: user history, raw database rows, wealth profiles, device
identifiers, files, source code, and all API keys or tokens. The sanitizer
enforces this even against the allowlisted projection. The system prompt forbids
invented numbers, recommendations, fatwas and unlisted citations; `temperature`
is fixed at `0`.

## Gates completed in code

1. **Explicit consent UI** — implemented: payload preview, per-request consent,
   cancel, and session-data removal; names the configured provider/model.
2. **Operations** — no keys in source, tests, docs, logs, URLs or provenance;
   runtime-entered keys only, sent only to the user-chosen provider; errors
   scrub the key; output numbers are guarded.

## Gates that still require the project owner's decision

These are **not** completed by the code and must be resolved before a hosted
provider is used for real or commercial data:

3. **Privacy** — document the chosen provider's retention, training usage and
   data location. User history is never sent by default and is never used to
   train a model. Cancellation and session-data removal must keep working.
4. **Cost** — set per-user/per-session quotas, show cost/latency expectations,
   and define what happens when the budget is exhausted.
5. **Model license** — verify the provider terms and the specific model license
   for the intended commercial use and redistribution, including output rights.
6. **Data-source terms** — re-check IMF SDMX terms, FMP terms, and every price
   vendor license before commercial use or redistribution. Preserve source URL,
   retrieval time, covered period, currency and unit with every value.
7. **Evaluation** — keep a held-out Arabic question set covering normal cases,
   zero denominators, missing data, unit/currency mismatch and mixed
   provenance. Measure that the coordinator still refuses to fabricate numbers,
   including through the hosted path.
8. **Dataset rights (only if fine-tuning)** — see below.

## Fine-tuning (optional phase 4 — not started)

Do not begin until all of the following hold: a question/answer set the project
legally owns, personal data removed, license reviewed, improvement measured on
a held-out set that was never used in training, and the project owner's written
decision. User logs and API keys are never training data.

## Permanent prohibitions

- No buy/sell recommendation, personal financial diagnosis or religious fatwa.
- No presenting synthetic or sample data as real market or wealth data, and no
  use of synthetic data in real reports.
- No silent replacement or modification of conflicting data; show source and
  date and ask the user to resolve the conflict.
- No arbitrary SQL and no database write without explicit confirmation.
- No numbers outside the deterministic engines and declared sources.

Decision log:
- 2026-11-17 — local coordinator and consent gate implemented; hosted transport
  deliberately left disabled pending the checklist above.
- 2026-11-18 — optional runtime-configured hosted transport added behind
  settings, per-request consent, sanitizer and numeric output guard. It remains
  off until configured and consented; provider privacy, cost, license,
  data-source terms and evaluation decisions (gates 3–7) remain with the owner.
