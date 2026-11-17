# Wasl AI — privacy, cost and license review gate

Status: **review pending**. The app ships with a local-only, deterministic
explanation coordinator. No hosted model is enabled, no model key is configured,
and no fine-tuning has been started.

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

## Exact hosted payload allowlist

If a hosted transport is ever enabled, it may receive only:

```
expert        enum name (equationTutor | metricExplainer | dataQualityReviewer)
question      free text entered by the user for this request
claims[]      kind, text_ar, text_en, equation_id?, provenance?, citations[]
citations[]   label, uri, retrieved_at?
```

Excluded, always: user history, raw database rows, wealth profiles, device
identifiers, files, source code, and all API keys or tokens. A sanitizer strips
sensitive keys and redacts credential-bearing URL parameters even from the
allowlisted payload. `AiPayload` itself has no key field.

## Gates that must be completed before enabling any hosted model

1. **Explicit consent UI** — already implemented; must stay visible and must
   name the provider and the data above before any network call.
2. **Privacy** — document provider retention, training usage and data location.
   User history is never sent by default and is never used to train a model.
   Cancellation and session-data removal must keep working.
3. **Cost** — set per-user/per-session quotas, show cost/latency expectations,
   and define what happens when the budget is exhausted.
4. **Model license** — verify the provider terms and the specific model license
   for the intended commercial use and redistribution, including output rights.
5. **Data-source terms** — re-check IMF SDMX terms, FMP terms, and every price
   vendor license before commercial use or redistribution. Preserve source URL,
   retrieval time, covered period, currency and unit with every value.
6. **Dataset rights (only if fine-tuning)** — see below.
7. **Evaluation** — keep a held-out Arabic question set covering normal cases,
   zero denominators, missing data, unit/currency mismatch and mixed
   provenance. Measure that the coordinator still refuses to fabricate numbers.
8. **Operations** — no keys in source, tests, docs, logs, URLs or provenance;
   runtime-entered keys only; send them only to their owning provider.

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

Decision log: 2026-11-17 — local coordinator and consent gate implemented;
hosted transport deliberately left disabled pending the checklist above.
