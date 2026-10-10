# ADR 0033 — Integer minor-unit (paise) amounts

Status: Proposed, planning only — 2026-10-10. Needs `@human` approval because
it amends the frozen normalized transaction record contract
(`lib/data/models/normalized_transaction_record.dart`) and
the on-disk schema (db-and-migrations checklist). Brief: [T-165c](../tasks/T-165c.md).

## Context

Money is stored and computed as IEEE-754 `double` in most places:
`transactions.amount` and `balance_after` are `RealColumn`
([table](../../lib/data/db/tables/transactions_table.dart#L36)),
`recurring_series.expected_amount/last_amount` are `RealColumn`
([table](../../lib/data/db/tables/recurring_series_table.dart#L15)), SQL
aggregates are `SUM(t.amount)` over REAL
([dashboard](../../lib/data/repositories/dashboard_repository.dart#L188),
[transactions](../../lib/data/repositories/transaction_repository.dart#L344)),
Dart folds use `fold<double>` ([claim](../../lib/intelligence/claim.dart#L281),
[insights](../../lib/intelligence/insights_engine.dart#L297)), correlators use
tolerances (`<= 0.01`, [correlator](../../lib/capture/event_correlator.dart#L174)),
the parser calls `double.parse`
([normalizer](../../lib/capture/template_engine/field_normalizer.dart#L268)), and
CSV export uses `toStringAsFixed(2)`
([export](../../lib/features/transactions/transaction_csv_export_service.dart#L51)).
Several places already patch around this: `amountPaise => (amount * 100).round()`
([record](../../lib/data/models/normalized_transaction_record.dart#L27)) and a
BigInt decimal-unit converter in the refund preview (ADR 0026,
[preview](../../lib/data/repositories/refund_link_preview_repository.dart#L593)).
Newer tables (`financial_events.net_amount_paise`, `expected_events.*_paise`,
`shadow_transactions.amount_paise`) are already integer.

Refund netting (T-100c), card liability sums (T-190f2) and budgets (T-098c)
all add and subtract many amounts and compare sums to caps; float drift makes
"exactly refunded", "cumulative <= original" and "remaining == 0" guards
unreliable.

## Decision

1. Add a `Money` value type (`int minor` + currency identity per ADR 0017). All
   new arithmetic, comparison and aggregation use integer minor units. `double`
   is allowed only for ratios, confidence, statistics and chart geometry.
2. Minor-unit exponent comes from a small ISO 4217 table (default 2; JPY/KRW/
   VND/CLP 0; KWD/BHD/OMR/JOD/TND 3). A null or unknown currency code uses
   exponent 2 and stays an unknown bucket; it is never presented as INR
   (ADR 0017). No FX conversion is introduced.
3. Storage is expand/contract. The next free schema version (v21 unless ADR
   0034's `sms_facts` migration lands first) adds nullable `transactions.amount_minor`,
   `balance_after_minor`, and `recurring_series.expected_amount_minor`,
   `last_amount_minor`, backfills them in the migration transaction, and keeps
   the legacy REAL columns untouched. Writers dual-write until a later
   contract release (v22, separate approval) stops writing/drops the REAL
   columns. Existing `*_paise` columns keep their names; their meaning is
   "minor units of the row's currency" (INR default) and the audit subtask
   confirms each has a currency.
4. Lossless conversion rule: convert via exact decimal text (shortest `double`
   string), never `x * 100`. If a value has more fractional digits than the
   currency exponent, the migration aborts before committing and reports the
   row count (no silent rounding); the pre-migration copy required by ADR 0012
   remains the rollback. Verification query after backfill:
   zero rows with `amount_minor IS NULL` or `amount_minor / 10^exp != amount`.
5. Backup: new archive version writes `amount_minor` and also the legacy
   decimal `amount`; restore accepts old archives (v1-v3: derive minor from
   `amount` with the same exact converter) and new ones (cross-check both when
   present; mismatch aborts restore). Older apps keep restoring new archives
   through the legacy field for one release.
6. Display and export format from minor units without passing through `double`.
   CSV output for INR stays byte-identical (`1234.50`).

## Consequences

Positive: exact sums, exact equality for refund and budget caps, simpler
SQL (`SUM(amount_minor)` is integer), parity tests can use exact equality.
Negative: touches ~45 files that read `.amount`; a dual-read period doubles
write paths; every SQL aggregate must be bucketed by currency so exponents are
not mixed (already required by ADR 0017).

## Alternatives considered

- Keep `double` + epsilon: rejected; drift accumulates in caps and sums.
- `Decimal` package: heavier and not stored natively; minor ints are SQLite
  native and index/aggregate cheaply.
- Fixed x100 for every currency: rejected; wrong for JPY/KWD fidelity.
- Per-row scale column: more general (ADR 0026 allows 6 decimals) but breaks
  `SUM` within a bucket; exponent-by-currency is simpler and enough for SMS
  data.

## Rollback

Until the contract release, legacy REAL columns remain authoritative-equivalent
and complete, so reverting readers to REAL is a code-only rollback. Binary
downgrade is not supported by Drift; use the ADR 0012 pre-migration snapshot or
an encrypted backup (which still carries legacy `amount`).
