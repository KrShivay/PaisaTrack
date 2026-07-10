# ADR 0005 — Fixture provenance tiers + parse-trust promotion via user confirmation

Status: accepted (@human proposed and approved, 2026-07-10)

## Context

Template packs require real SMS fixtures (fixture-first law, T-024), but users
of untemplated banks (Kotak, Central Bank) will not share SMS dumps — raw bank
SMS is sensitive and the trust barrier is legitimate. Meanwhile real Kotak/
Central messages are publicly posted (forums, parser repos), with weaker
provenance: transcription rot, staleness, selection bias, and — critically —
no bank-statement ground truth behind the expected parse. Templates parse at
0.97 → silent auto-label, so a template built on a subtly-wrong format could
quietly corrupt data. The generic parser (T-066) already covers these users at
<=0.6 (always reviewed), so templates are a precision upgrade, not a fix.

## Decision

Three-tier fixture provenance, with user confirmation as the promotion path:

1. **`device` (gold).** Pulled from a real device by the owner, sanitized,
   statement-reconcilable. Templates built on them parse at 0.97 (unchanged).
2. **`public` (silver).** Sourced from public postings. Admitted into
   `test/fixtures/sms/` with `"provenance": "public"` in the expected JSON and
   in the template entry. Loader caps such templates' parse confidence at
   **0.85** — inside the ask/review band, so they can NEVER silently
   auto-label. Their errors surface as asks, not corrupted rows.
3. **Promotion by evidence.** The app asks users (on low-trust parses:
   public-provenance templates and generic parses) to confirm the parse
   itself — amount/direction/merchant, not just category. Confirmations and
   parse-field corrections are recorded as feedback rows (`field:
   'parse_verdict'`, context 'parse_confirm'). A per-template trust ledger
   promotes a public template to 0.97 after >=20 confirmed parses with zero
   amount/direction corrections; any amount/direction correction demotes it
   back and flags the template for re-authoring. Donated sanitized fixtures
   (in-app preview-and-approve export flow) promote immediately to `device`.

The existing correction machinery is reused, not duplicated: `correctWithRule`
already funnels one-write feedback; parse confirmation extends the feedback
row vocabulary and feeds the same Phase 3 learning loop (adaptive thresholds,
T-054, generalize naturally to parser trust).

## Consequences

- Kotak/Central templates can ship now from public fixtures; worst case is a
  few extra asks until confirmed — the decision-policy band absorbs the risk.
- The confirmation surface doubles as training-data collection: every verdict
  is a labeled example for Phase 3 models. Intelligence improves as a side
  effect of users protecting their own data quality.
- Fixture files and template JSON gain a provenance field; absence means
  `device` (back-compat with all existing fixtures).
- The fixture-first law is amended, not repealed: fabrication remains
  forbidden; public sourcing is admitted only with the cap + promotion rules.
