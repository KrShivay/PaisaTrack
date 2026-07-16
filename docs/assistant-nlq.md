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

The model never writes SQL and never answers directly.

## Supported intents

- period total: spend, income, or net;
- category breakdown;
- merchant lookup;
- period comparison;
- upcoming recurring items;
- active deterministic insights.

Filters are limited to validated category, literal merchant text, direction,
and bounded time ranges. Unknown fields, categories, dates, aggregations, or
intent names are refused.

## Query rules

- Spending excludes transfers, duplicate echoes, soft-deleted rows, and future
  excluded payment sources.
- Merchant text is treated literally; wildcard characters cannot broaden it.
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
