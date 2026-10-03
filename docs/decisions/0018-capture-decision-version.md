# ADR 0018 — Version capture decisions in existing provenance

Status: accepted; v2 decision contract, 2026-10-02.

## Context

The initial T-177a audit found that parsed transactions persisted parser,
merchant, and category provenance in `transactions.confidence_json`, but the
final category/status decision had no version. A replay therefore could not
distinguish a versioned capture decision from a legacy row. Its 2026-09-30
path matrix accurately recorded that history and resume then omitted merchant
resolution. Commit `f730857` added the resolver to those paths on 2026-10-02;
the 2026-10-03 reconciliation records the current wiring. All three paths now
run `MerchantResolver`. Live may use the optional parser field locator and
permits embedding-similarity search suggestions; history and resume use
template+generic parsing and pass `allowSuggestions: false`, which skips that
new embedding search. Previously stored learned/similarity aliases can still
return a `needsReview` suggestion in any path.

History and resume normally keep non-rule decisions in review. Settled
duplicates take a direct `auto` branch before source-evidence write guards;
unsettled rows still require review. Rule hits still run the status policy,
preserving eligible `auto` results while clamping `asked` to `needs_review`;
the live path also honors a merchant resolver's `needsReview` similarity
signal before accepting a rule-backed status. These exceptions are part of
the decision contract, not an assertion that all imported rows are
review-only.

## Decision

For a parsed transaction created by `SmsIngestor`, add this metadata to the
existing `confidence_json` object:

```json
"capture_decision": {
  "version": "capture-decision-v2",
  "status_mode": "policy",
  "category_source": "rule"
}
```

The persisted block records the provider's status mode: `policy` for live and
`fixed_review` for history/resume, including rule hits. A confirmed rule hit
records `category_source: rule`. Other rows record the categorizer source. The
write guard may still downgrade a decision when required source evidence is
missing.

Rule matching order is exact counterparty VPA, resolved merchant ID, exact
normalized merchant identity, then a merchant word-boundary fallback for
`merchant_legacy` rules. The VPA tier comes first because a per-VPA correction
is narrower than a merchant-wide correction and must not be shadowed. R3
stores the merchant ID in the existing rule `match_type`/`match_value` columns
as `merchant_id` / the merchant ID. A row uses that tier only when persisted
`confidence_json.merchant.src` identifies an exact resolution (`user`,
`exact`, or `new`); missing provenance and fuzzy suggestion/similarity links
fall back to the R1 exact VPA/name rule. ID sweeps include exact-source linked
rows and unresolved rows whose VPA or evidence name exactly matches the
corrected row. Fuzzy/legacy linked rows are excluded unless those exact
identifiers match. This adds no column and does not reinterpret or rewrite
rules created before R3. Undo keeps restoring the exact prior rule rows as
before. Schema v19's data-only, idempotent migration tags existing `merchant`
rows as `merchant_legacy`, with no new columns. Backups mark the rule-matching
semantics they contain; restore tags unmarked older `merchant` rules as legacy
and preserves exact rules from current backups. Newest wins within each tier.
This keeps legacy rules such as `amzn` working while a corrected `Swiggy` rule
cannot claim `Swiggy Instamart`. Unresolved existing-and-future corrections
use exact normalized payee evidence through its existing index. The v20 re-key
and unresolved-row backfill remain deferred as described in T-177.

Rollback to a pre-R3 app leaves `merchant_id` rules inert because that app does
not recognize the match type. If merchant merges or deletes are introduced,
the v20 plan must define how to reassign or surface dangling `merchant_id`
rules before enabling those operations.

The version identifies the category and initial transaction-status decision
contract, including its guards. Parser versions remain in `raw_sms.parser_version`;
parser, merchant, and category field provenance remain in their current blocks.
This identifier carries no source text, user label, merchant identity, or model
output. It does not assert that a prediction was reviewed or correct.

The shared capture-decision contract owns both the writer and the reader. The
reader returns no version for absent, malformed, or unsupported metadata. Old
rows are not backfilled or treated as if they used the current version. A
future behavior change to category/status decision semantics must use a new
version string; changing parser-only behavior continues to use the parser
version. The earlier writer emitted v1; those rows retain that marker and are
not retroactively reclassified. The reader accepts only v2 and supported status
modes; absent, malformed, or unknown values remain unsupported. v1 rows remain
readable through their existing parser, merchant, and category fields but are
not treated as v2 decision evidence.

This is an additive JSON key in an existing text column. It needs no database
migration or generated code. Existing confidence readers continue to read
`parser`, `merchant`, and `category` as before. Encrypted backups already retain
the full `confidence_json` value, so restore preserves the metadata; transaction
deletion removes it with its owning row. Raw-SMS retention and deletion rules do
not change.

## Scope and consequences

The version is evidence of which decision contract produced a row, not a
measurement of accuracy. Replay remains synthetic and selected explicit
feedback remains non-holdout evidence. v2 changes fixed-review status handling
for rule hits and restores the live similarity-alias review guard. Parser,
inference, and rollout behavior remain unchanged. Real holdout, physical
capture, and rollout decisions remain open under T-177a/f.
