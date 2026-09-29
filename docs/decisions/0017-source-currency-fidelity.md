# Source currency is part of transaction identity

Status: accepted for T-187

## Context

The transaction ledger stores a number without its source currency. An Axis
template accepts both `USD` and `INR` but captures only the numeric portion;
the recurring detector and analytics then compare and add these values as if
they were INR. A bare `$` is also ambiguous among several ISO currencies. A
display-only formatting fix would leave recurring detection, questions, and
financial totals incorrect.

## Decision

- Carry a nullable ISO currency code and the source symbol alongside each
  normalized transaction amount. `null` means the source did not establish an
  ISO code; a captured `$` remains available as a distinct symbol bucket.
- Preserve nominal amounts exactly as parsed. No network FX lookup, guessed
  rate, or implicit conversion is allowed. Explicit source evidence such as
  `USD`, `US$`, `INR`, `Rs`, or `₹` determines the code. Bare `$` remains an
  unknown-code `$` bucket.
- Include currency identity in recurring grouping, amount clustering, stable
  identities, series rows, and status memory. Keep recurring totals and
  analytics separated by currency. INR budgets consume INR rows only.
  Expected-event reconciliation compares only matching source-currency
  buckets; unknown legacy reminders can match only unknown legacy debits.
- Add nullable transaction and recurring-series columns. Rows whose currency
  cannot be recovered from existing normalized evidence remain unknown. A
  still-retained raw SMS may be used for an exact source-backed backfill; raw-SMS
  retention is not extended.
- Keep archive restoration compatible with v1 JSON and older chunked archives
  that omit the new optional fields.

## Consequences

The transaction schema, parser contract, assistant result types, analytics
aggregates, reminder reconciliation, recurring UI, archive import, and their
tests change together. An
unknown currency is displayed and queryable as unknown (and, where captured,
with its original `$` symbol); it is never presented as INR. Previously parsed
Axis messages without retained source SMS cannot be distinguished between USD
and INR and therefore remain unknown.
