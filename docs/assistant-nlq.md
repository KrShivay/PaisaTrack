# In-app Assistant Grounding Contract

The assistant may interpret questions, but every financial fact and number must
come from deterministic code over the local database.

## Flow

```text
question
  → AssistantIntentClassifier (common deterministic path)
  → compact LlmRuntime intent fallback when needed
  → IntentValidator
  → AssistantQueryEngine
  → AnswerRenderer
```

Curated suggestions are defined in
`lib/intelligence/assistant/prompt_catalogue.dart`. The catalogue is shared by
the assistant UI and its contract test, which classifies and validates every
question before it can ship.

The model never writes SQL and never answers directly.

## Supported intents

- period total: spend, income, or net;
- category breakdown;
- merchant lookup;
- period comparison;
- upcoming recurring items;
- active deterministic insights.

Filters are limited to validated category, payee identity, direction, and
bounded time ranges. Payee phrases resolve across user labels, aliases, and
captured VPA/payee evidence with whole-phrase matching; multiple matches prompt
for clarification. Unknown fields, categories, dates, aggregations, or intent
names are refused.

## Query rules

- Spending excludes transfers, duplicate echoes, soft-deleted rows, and future
  excluded payment sources.
- Payee identity matches do not use SQL wildcards or raw substring matching.
- Payee answers disclose included names and the matched evidence in the
  “How this was counted” section.
- Recurring and insight answers relay stored deterministic results.
- Empty data returns an honest empty answer, not an invented zero narrative.
- Future budget/refund/source answers require typed QueryEngine results before
  they can be added as assistant intents.

## Rendering invariant

`AnswerRenderer` receives only a typed intent and typed query result. It has no
parameter for raw model output. Tests must prove every rendered digit is
traceable to a query-result field.

## Refusal and privacy

- Unsupported, advisory, malformed, or ambiguous questions receive a fixed
  refusal plus safe example questions.
- No investment or prescriptive financial advice.
- Questions, prompts, intents, database results, and answers remain on-device.
- Conversation history is session-only and is not persisted.
- The only network path is explicit model download, which contains no user data.

## Extension rule

Adding an intent requires a typed validator model, one deterministic query
method, fixed renderer output, seeded exact-result tests, refusal tests, and a
privacy review. Never expand the model into a free-form answer generator.

## Current implementation and planned extension

The 2026-09-26 spending-query parity finding was closed in T-178a. Current
eligibility, payee matching, and currency behavior is documented in
[architecture](architecture.md#grounded-assistant) and covered by the query
contract tests. Income queries retain their own explicit semantics.

[T-178](tasks/T-178.md) plans typed evidence-linked insights, forecast ranges and
English/Hinglish questions; estimates remain separate from facts. The model
cannot generate SQL or bypass the fixed renderer. See the
[AI report](reports/grounded-ai-opportunities.md).
