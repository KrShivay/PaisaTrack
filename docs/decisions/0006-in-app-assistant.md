# ADR 0006 — In-app assistant (on-device NL Q&A over local data)

Status: accepted (@human proposed 2026-07-10; groomed at @human's direction)

## Context

PLAN Phase 4 already reserves an on-device LLM layer (extraction fallback for
unmatched SMS + monthly narrative insights; feature-flagged; optional model
download; inference never leaves the device per ADR 0002). @human wants an
in-app AI the user can talk to. A conversational assistant is NEW scope beyond
PLAN Phase 4 — this ADR admits it and fixes its safety envelope.

## Decision

Add **T-076 "ask your money anything"** to Phase 4, on the same runtime
foundation (T-075) as the planned extractor/narratives:

- **Grounded, never generative about numbers.** The LLM translates the user's
  question into a constrained intent JSON (metric, category/merchant filters,
  time range, aggregation) validated against a whitelist; a deterministic
  QueryEngine executes it over repositories; the reply interpolates ONLY
  numbers computed by SQL. The model never emits free-form SQL and never
  invents figures.
- **Local-only.** Prompts and answers never leave the device (ADR 0002). The
  only network touch in the whole layer is the user-initiated model download
  (static asset fetch, integrity-checked, not bundled in the APK).
- **Scope guardrails.** Answers only from the user's own data; no investment
  or financial advice framing; forecast statements only relay the
  deterministic forecaster's (PLAN §7.8) outputs.
- **Ordering.** Gated on Phase 3 exit (T-064): the assistant's value comes
  from the enriched substrate (recurring, baselines, insights). The runtime
  foundation (T-075) is Phase-3-parallel safe (new module, no file overlap)
  and slots after the Phase 2.5b trust loop.

## Consequences

- PLAN §Phase 4 text amended to include the assistant and its exit criterion:
  every number in an assistant answer is traceable to a QueryEngine result
  (asserted in tests); intents outside the whitelist refuse gracefully.
- The intent whitelist becomes the assistant's contract; growing it is normal
  feature work, each intent with its own tests.
- Model download UX, storage, and delete control are owned by T-075 and shared
  by extractor, narratives, and assistant.
