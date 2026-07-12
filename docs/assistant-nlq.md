# In-app Assistant — NLQ Grounding Contract (Spec, T-083)

Status: review-ready spec, 2026-07-12, @claude. Specifies T-076 ("ask your
money anything") ahead of implementation, per COLLABORATION §2 and the same
spec-before-build pattern as the T-066 parser spec. Fixes the safety envelope
set by ADR 0006 into an implementable contract.

## Motivation

@human wants an in-app AI the user can talk to about their money (ADR 0006).
The hard requirement is that the assistant is **grounded, never generative
about numbers**: every figure in an answer must be computed by deterministic
code over the local database, never produced by the language model. The model's
only job is to translate a natural-language question into a **constrained intent
JSON** that a deterministic `QueryEngine` executes. The model never sees or
emits SQL, and never invents a number. This spec defines the intent schema, the
whitelist, the intent→repository mapping, the grounding contract, and the
refusal, no-advice, and on-device rules.

## Position in the flow

```
AssistantController.ask(userText):
  1. LlmRuntime.extractJson(userText, intentSchema)   → candidate intent JSON (T-075)
  2. IntentValidator.validate(candidate)              → typed Intent | RefusalReason
  3. QueryEngine.run(Intent)                          → QueryResult (numbers only, from repos)
  4. AnswerRenderer.render(Intent, QueryResult)       → reply string (interpolates ONLY QueryResult)
```

The model participates in step 1 only. Steps 2–4 are pure Dart with no model in
the loop. If step 1 yields anything the validator rejects, the assistant refuses
gracefully (see Refusal) — it never falls back to letting the model answer
free-form.

Everything is behind the `AppConstants.enableLocalLlm` feature flag (default
off). With the flag off, or with no downloaded model, the assistant surface is
not shown and no code path here runs.

## The constrained intent JSON

The model is prompted to emit exactly one JSON object of this shape. It is the
**only** thing the model produces; it is never shown to the user.

```jsonc
{
  "intent": "period_total",          // one of the whitelist ids below — REQUIRED
  "metric": "spend",                 // "spend" | "income" | "net"
  "filter": {                        // all fields optional; absent = no filter
    "category": "Food",              // resolved to a category id by the validator, not the model
    "merchant": "Swiggy",            // free text; resolved deterministically downstream
    "direction": "debit"             // "debit" | "credit"
  },
  "time_range": {                    // REQUIRED for every intent except active_insights
    "kind": "month",                 // "month" | "last_n_days" | "range" | "all_time"
    "month": "2026-07",              // when kind=month (YYYY-MM)
    "n_days": 30,                    // when kind=last_n_days
    "start": "2026-06-01",           // when kind=range (inclusive)
    "end": "2026-06-30"              // when kind=range (inclusive)
  },
  "aggregation": "sum",              // "sum" | "count" | "average" | "breakdown"
  "compare_to": {                    // present ONLY for month_over_month
    "kind": "month", "month": "2026-06"
  }
}
```

Rules the validator enforces (the model is asked to follow them, but the
validator is the authority — a violating field is a refusal, never a guess):

- `intent` MUST be one of the whitelist ids. Unknown id → refuse.
- The model NEVER emits SQL, table names, column names, or free-form
  expressions. The schema has no field that can carry them; any such content is
  dropped by the validator.
- `category`/`merchant` are hints only. The validator resolves `category`
  against the user's real category list (exact, then case-insensitive match);
  an unresolvable category is refused with a suggestion, never silently widened.
  `merchant` is passed to the QueryEngine as a normalized `LIKE` term over
  stored merchant names — the model never influences the SQL, only supplies the
  literal to bind.
- All dates are validated as real calendar dates; ranges must be start ≤ end and
  not in the future beyond today (device clock). Out-of-bounds → refuse.

## Intent whitelist (MVP)

Exactly these six intents ship in the MVP. Each is a closed template; growing
the list is normal feature work, each with its own tests (ADR 0006).

| id | question shape | required fields | QueryEngine template |
|----|----------------|-----------------|----------------------|
| `period_total` | "how much did I spend in July" | metric, time_range, aggregation=sum/count/average | SUM/COUNT/AVG of signed amount over transactions in range, optional category/merchant/direction filter |
| `category_breakdown` | "where did my money go last month" | time_range, aggregation=breakdown | GROUP BY category_id over range, ordered by total desc |
| `merchant_lookup` | "how much at Swiggy this month" | filter.merchant, time_range | SUM + COUNT over transactions whose resolved merchant matches, in range |
| `month_over_month` | "am I spending more than last month" | metric, time_range, compare_to | two period_total runs (range + compare_to), returns both totals + delta + pct |
| `upcoming_recurring` | "what subscriptions are due soon" | time_range (defaults next 30 days) | recurring_series rows with next_due within range, ordered by next_due |
| `active_insights` | "anything unusual lately" | (none; time_range optional) | non-dismissed rows from the insights table for the current period |

Any question the model cannot map onto one of these six → the model is
instructed to emit `{"intent": "unsupported"}`, which the validator turns into a
graceful refusal.

## QueryEngine mapping (deterministic, model-free)

The QueryEngine is pure Dart over the existing repositories — it is the single
source of every number:

- **transactions** → `TransactionRepository` (period totals, breakdowns,
  merchant lookups, month-over-month). Amounts are read as stored; the engine
  applies the metric (spend = debits, income = credits, net = signed sum).
- **recurring_series** → recurring repository (upcoming_recurring: `next_due`
  within range). Relays the deterministic recurring detector's rows (PLAN §7.6);
  the engine does not re-forecast.
- **baselines** / **insights** → insights repository (active_insights, and any
  forecast/anomaly figures a reply cites). Forecast statements relay ONLY the
  deterministic forecaster's stored outputs (PLAN §7.8) — the assistant never
  computes or embellishes a projection.

Every QueryEngine method returns a typed `QueryResult` carrying labeled numeric
fields (and, where relevant, the row ids they came from) — never a prose string.
Each intent maps to exactly one QueryEngine method; there is no dynamic query
construction and no model-supplied SQL fragment anywhere in the path.

## Grounding contract (the safety property)

1. **Numbers come only from QueryResult.** `AnswerRenderer` builds the reply
   from a fixed template per intent and interpolates ONLY fields present on the
   `QueryResult`. It has no access to the raw model text at render time.
2. **No model-originated figures.** A renderer test MUST prove this: feed the
   renderer a `QueryResult` while a hostile/garbage model output is in scope and
   assert every digit in the rendered reply is traceable to a `QueryResult`
   field (e.g. render with known result values and assert the output contains
   exactly those, and that a planted bogus number from the model never appears).
   This is the T-076 exit criterion from ADR 0006.
3. **Currency and rounding** are formatted by the renderer (one helper), so the
   model can never influence how a number reads.

## Refusal behavior

The assistant refuses gracefully — it never guesses and never lets the model
answer numerically — in each of these cases, returning a short message plus up
to three suggested in-whitelist questions:

- `intent` is `unsupported` or not in the whitelist.
- A required field is missing or malformed (bad date, empty range, unknown
  aggregation).
- `category` does not resolve to a real category ("I don't see a category
  called 'X' — did you mean 'Food' or 'Groceries'?").
- The query is well-formed but the data is empty for the range (answer with the
  zero/empty result honestly, e.g. "No transactions found for June" — this is a
  valid answer, not a refusal, but it must never be padded with an invented
  figure).

Refusals are deterministic (validator output), not model-authored.

## No-advice framing

The assistant reports facts from the user's data only. It does NOT give
investment or financial advice, recommendations, or judgments ("you should cut
back"). Forecast/anomaly statements relay the deterministic engines' outputs
verbatim in tone (PLAN §7.8/§7.7) without prescriptive framing. The renderer
templates are written to be descriptive; there is no free-form advisory text
path.

## On-device / privacy (ADR 0002, 0006)

- Prompts, the user's question, the intent JSON, and the answer NEVER leave the
  device. The assistant runs entirely on `LlmRuntime` (T-075), whose only
  network touch is the user-initiated, integrity-checked model download.
- On-device prompts may include raw transaction context per PLAN §8; no raw SMS
  is placed in a prompt beyond what the on-device model already handles for the
  extractor. No assistant text is logged in release builds.
- Session-scoped history only: conversation context lives in memory for the
  session and is not persisted.

## Non-goals

- No new metrics or intents beyond the six above (each future intent is its own
  task + tests).
- No free-form/model-authored numeric answers, ever — out of whitelist refuses.
- No advice, recommendations, or projections the deterministic engines didn't
  already produce.
- No cloud inference, no network call carrying user data (ADR 0002).

## Test plan (for T-076)

- **Grounding property (the exit criterion):** renderer test proving every digit
  in a reply is traceable to a `QueryResult` field; a planted model-originated
  number never surfaces.
- **Validator:** table-driven over each whitelist intent (valid → typed Intent)
  and over malformed/unsupported/unknown-category/bad-date inputs (→ typed
  refusal). Assert the model can never smuggle SQL/table/column strings through
  any field.
- **QueryEngine:** per-intent unit tests over a seeded in-memory DB with known
  totals — assert exact numbers for period_total, breakdown ordering,
  merchant match, month-over-month delta/pct, upcoming_recurring window, and
  active_insights (non-dismissed only).
- **Refusal UX:** out-of-whitelist question yields a refusal with ≤3 valid
  suggestions and no numbers.
- **Flag/degrade:** with `enableLocalLlm=false` or no model, the assistant
  surface is absent and no QueryEngine call is made.
- **Network-free:** the inference path makes no network call (only the T-075
  download abstraction may), asserted with a fake runtime.
