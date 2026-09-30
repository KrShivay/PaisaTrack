# ADR 0018 — Version capture decisions in existing provenance

Status: accepted for the bounded T-177a milestone, 2026-09-30.

## Context

T-177a now exercises the production live, history, and resume providers with
synthetic messages. Parsed transactions persist parser, merchant, and category
provenance in `transactions.confidence_json`, but the final category/status
decision has no version. A replay therefore cannot distinguish a versioned
capture decision from a legacy row. The three providers intentionally differ:
live may use the optional parser field locator and merchant resolver, while
history and resume use template+generic parsing, omit merchant resolution, and
force review status.

## Decision

For a parsed transaction created by `SmsIngestor`, add this metadata to the
existing `confidence_json` object:

```json
"capture_decision": {
  "version": "capture-decision-v1",
  "status_mode": "policy"
}
```

The persisted block records `status_mode` as `policy` for live capture or
`fixed_review` for initial history/resume import. This makes the intentional
path difference explicit even when the version of the shared decision contract
is the same.

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
version. The reader accepts only the supported version and status modes; absent,
malformed, or unknown values remain unversioned.

This is an additive JSON key in an existing text column. It needs no database
migration or generated code. Existing confidence readers continue to read
`parser`, `merchant`, and `category` as before. Encrypted backups already retain
the full `confidence_json` value, so restore preserves the metadata; transaction
deletion removes it with its owning row. Raw-SMS retention and deletion rules do
not change.

## Scope and consequences

The version is evidence of which decision contract produced a row, not a
measurement of accuracy. Replay remains synthetic and selected explicit
feedback remains non-holdout evidence. This ADR does not change parser,
merchant-resolution, categorizer, history/resume status, inference, or rollout
behavior; the existing path differences remain documented and tested. Real
holdout, physical capture, and rollout decisions remain open under T-177a/f.
