# ADR 0034 — Source-faithful SMS facts store (schema v21)

Status: Accepted (owner, 2026-10-10), including the narrow ADR 0021 retention
amendment in Decision 4. Not yet implemented (T-207j onward). Ask/insight
wording for balances is "balance per last SMS, as of <date>" with a staleness
label (orchestrator default; never a promised or live balance).
Schema version numbers here are provisional; see the allocation rule in
[schema](../schema.md#planned-additive-areas).

## Context

Bank/card/investment SMS carry far more than the amount: available balance,
credit limit, total/min due, due date, statement date, mandate/UMRN, EMI and
loan numbers, folio/NAV/units, interest credited, merchant city, card network,
terminal, UPI app, IFSC. Today the pipeline keeps three of these at most:

- `FieldNormalizer` reads only the named groups `amount, account, date,
  merchant, vpa, ref, balance` (`lib/capture/template_engine/field_normalizer.dart`);
  only 10 of 37 bundled templates capture `balance`, and the value lives only
  in `transactions.balance_after` (`transactions_table.dart:48`), so there is
  no per-account balance history.
- `balance`, `statement`, `otp`, `promo`, `unknown` messages are marked
  processed and dropped (`sms_ingestion.dart:395-412`); unlinked raw SMS then
  expire after 7 days (ADR 0021), so due dates, limits and statement totals
  are lost.
- `SupportingSmsInfo` keeps a due date in memory only (ADR 0032).

## Decision

1. Add table `sms_facts` (schema v21): one row per extracted, span-verified
   fact. A fact is a typed value plus its evidence; it is never a transaction
   and never alters one.

   | column | type | note |
   |---|---|---|
   | `id` | text PK | UUID |
   | `sms_id` | text | provenance; no FK (like `sms_transaction_links`) |
   | `transaction_id` | text null | set when the SMS also produced a txn |
   | `payment_source_id` | text null | resolved read-only from last-4/masked id; never creates a source |
   | `kind` | text | closed registry, e.g. `balance_available`, `credit_limit_available`, `due_total`, `due_min`, `due_date`, `statement_date`, `mandate_ref`, `emi_amount`, `loan_outstanding`, `mf_nav`, `mf_units`, `interest_credited`, `merchant_city`, `card_network`, `terminal_id`, `upi_app`, `ifsc` |
   | `value_paise` | int null | integer paise; amounts never doubles |
   | `value_milli` | int null | units/NAV scaled by 1e3 (units) or 1e4 (NAV); kind decides |
   | `value_text` | text null | identifiers, enums, city; masked where PII (see below) |
   | `value_date` | int null | UTC day epoch for dates stated in the SMS |
   | `currency_code` | text null | ADR 0017 |
   | `verbatim` | text | exact quoted span, max 80 chars |
   | `span_start`,`span_end` | int | offsets into the SMS body at capture |
   | `extractor` | text | `rule` \| `template` \| `llm_located` |
   | `extractor_version` | int | pattern-pack version |
   | `observed_at` | int | SMS `receivedAt` (epoch ms) |
   | `status` | text | `verified` \| `conflicted` \| `superseded` |
   | `dedup_key` | text unique | hash(kind, source/sms scope, value, observed day) |
   | `created_at` | int | |

   Indexes: `(payment_source_id, kind, observed_at)`, `(sms_id)`,
   `(kind, value_date)`.
2. Verification reuses the `SpanVerifier` contract: `body.substring(start,end)
   == verbatim` at capture and re-parsing `verbatim` through the shared
   normalizer reproduces the stored value. A fact that fails is not written.
   `llm_located` facts additionally need the verbatim span to match a
   deterministic pattern-family for the kind (ADR 0011); the model never sets
   a value, date or reference.
3. Masking: `value_text` for account/loan/folio/UMRN/terminal/IFSC stores only
   the last 4 characters plus length class (`xx1234`) unless the kind is a
   public identifier (IFSC, card network, UPI app, city). Full tokens remain
   only in the retained raw SMS.
4. Retention (amends ADR 0021 narrowly): a raw SMS is "linked" if any
   `sms_facts` row references it AND that fact is the newest `verified` fact
   for its `(payment_source_id|sms scope, kind)`, or a due/statement fact whose
   `value_date` is within the next 45 days / last 90 days. Other fact-only
   SMS still expire at 7 days; their facts survive with `verbatim` as the
   durable evidence (span re-verification then reports `body_purged`, not
   failure). This bounds raw-SMS growth (one retained SMS per source per kind).
5. Facts are included in encrypted backup/restore (restore order after
   `raw_sms`, `payment_sources`, `transactions`), are wiped by
   delete-everything, and are rebuilt (not trusted) when `extractor_version`
   bumps: re-extraction marks old rows `superseded`.
6. Facts feed read-only consumers (timelines, insights, Ask, dashboard cards).
   Analytics totals (`net spending contract`) never read facts.

## Consequences

- Capture is unaffected: extraction runs after the raw SMS and transaction are
  persisted, inside try/catch behind a feature flag; failure leaves the SMS
  outcome unchanged.
- Cost: one table, ~1-6 rows per financial SMS. Backfill is nightly, bounded.
- Rollback: flag off stops writes; table is additive, so downgrade needs no
  data migration (v21 -> v20 drops the table).
- Credit-card ownership/accounting stays with ADR 0020/T-190; card facts are
  observations ("as of this SMS"), not ledger entries.

## Alternatives rejected

- Extra nullable columns on `transactions`: most fact SMS have no transaction.
- Keeping only the latest value in `payment_sources`: loses history, evidence
  and the ability to chart or explain.
- Storing the full SMS in facts: duplicates the most sensitive string.
