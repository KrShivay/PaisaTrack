# T-201 transaction-integrity audit

Baseline: main `dcfdab4`, 2026-10-04. Three Luna High read-only audits, with Sol
independent source review. This document distinguishes confirmed production
defects from latent helpers and unresolved product/device contracts.

| Reported issue | Source finding and disposition |
| --- | --- |
| OTP/security footers, failed-payment credits, unauthorized substring | Pre-fix regressions reproduced CBI debit → OTP, IndusInd returned credit → failed and only 3/6 fixture transactions created. Reviewed clause/token guards now pass the seven bank fixtures, including CBI credit 150 rather than its lakh balance, plus primary-OTP and negated-credit/authorization controls. |
| Failed/pending root suppresses settled retry | Shared rule and callers now require equal known lifecycle states. Settled retries survive failed/pending roots; settled echoes remain suppressed. Existing suppressed rows are not rewritten. |
| Live/inbox identity | Physical RecoveryQA reproduced different IDs from the production receiver and inbox reader for an identical synthetic alert with received DATE 60 seconds after DATE_SENT. Sent-time identity with exact legacy receipt-hash compatibility is in progress under ADR 0030; post-fix physical evidence and acceptance checks remain pending. |
| Processing errors never retried | Live, batch and catch-up share terminal decisions. Current-version processing errors retry once per unique ID per run; next runs can retry again. A bounded failure tracker stops with an incomplete result, and forced imports replace stale checkpoints while preserving completed-version evidence. |
| Commitment totals | Totals now use every active non-income INR series due in the current calendar month, separate from the three-item display cap. The existing monthly normalization helper shares eligibility without supplying the total. |
| Assistant upcoming payments | Ask now shares active recurring expense eligibility while preserving date windows and currency buckets. Income and disabled/unknown statuses abstain. |
| Category Undo | Both detail entry paths use guarded receipts and reload category caches without reseeding notes. All-target source/post-state and relevant feedback preflight precedes mutations. Nullable category/status and explicitly changed description restore; later edits block the entire Undo. Fresh rule IDs prevent same-second ownership ABA. |
| Owned transfers | Existing reconciliation requires different known four-digit masked-account suffixes. Equal suffixes across mask styles or all-mask/unknown identities abstain. No source merge; fresh automatic reconciliation remains gated by ownership/confirmation contracts. |
| Numeric VPA category | Shape alone no longer assigns full-confidence non-spending Transfers. Conservative Other fallback uses the existing asked/review policy; explicit rules and historical edits remain authoritative. |
| Template dates | Numeric and alphabetic constructors now validate round trips and use existing receive-time fallback for invalid components, including impossible leap dates. |
| Expected reminders | Reminder amount parsing accepts terminal punctuation. Snoozed rows reconcile at their rescheduled date with original-state/date guards. Missing identity or invalid amount stays unresolved; exact currency/amount/window/one-payment/ambiguity guards remain. |
| Description rules | New captures consume descriptions from explicit matching user rules. Model/memory descriptions are ignored; existing transactions are not rewritten. |
| Foreground recurring duplicates | Foreground and nightly callers now share complete projection cleanup. Absent detected IDs are pruned only after successful detection, and latest user status memory is reconciled transactionally across changed IDs, temporary non-detection and concurrent user changes. |
| EventCorrelator | Correlation methods are test-only; static reference helpers are used by duplicates. Unsafe latent auth/settlement assumptions must not be wired into production. Refund/card contracts remain open. |
| Evidence list | Valid claim IDs are deliberately capped at 50, so current evidence pages have no continuation and the reported wrong Load more button is not reproduced for that caller. Full evidence navigation is a product gap, not proof of a live button defect. |

## Verification limits

The initial physical probe returned `acceptedByLiveReceiver=true`,
`acceptedByInboxReader=true`, `idsMatch=false`, `dateSentRequested=false` and
`timestampDifferenceMillis=60000`. It used a fixed 3GPP PDU and an injected
cursor on Android 16/API 36, with no SMS permission or provider reads. The
post-fix probe must also demonstrate receipt-time keyset paging and the old
receipt-hash alias. Compatibility review includes purged provenance,
transaction/disposition pairs, conflicting claims and bounded catch-up.

The first post-fix integration attempts installed and launched only RecoveryQA.
Its Dart VM started, but the forwarded test connection closed before the probe
marker appeared. This is not a passing post-fix device check. Before the final
adjacent-page guard, 76 focused identity tests, analyzer and Android unit tests
passed; those results require a rerun after that guard. Full-suite and final
graph acceptance remain pending. After the bounded adjacent-page cohort guard,
79 focused tests and analyzer pass; an independent Luna review and Sol source
review found no remaining issue within the accepted identity scope. Native unit
tests passed before the final Dart-only changes. Post-fix physical evidence,
full-suite acceptance and final graph review still remain open.

Capture repairs pass a combined 153-test focused suite, analyzer, formatter,
diff checks and Android unit tests. Independent review caught and corrected
duplicate failure counting, stale forced-scan cursors and negated authorization
or refund cues. These focused results do not replace final full-suite/timezone
acceptance or the post-fix physical identity proof.

The QA-only explicit-action native fallback passes normal and QA Android unit
runs (33 tests) and QA APK compilation. Its marker allowlist contains selected
booleans and the synthetic timestamp offset, with no message or identity values.
APK app ID is `com.paisatrack.recoveryqa`, debuggable is true and its manifest
has no SMS permissions. SHA-256:
`d9a7c77c6f41a0a1e38374b6a0f33b7c7ebe9dc0d5538489fa72131bc11a4a57`.
The phone was absent from the device list and the previous endpoint did not
connect within 30 seconds. No fallback install/launch or log read occurred;
post-fix physical proof remains pending. The fallback bypasses the failed
Flutter forwarding path; repairing that connection is the proper runner fix.

No owner SMS, database, GUI, screenshots, logs, backups or keys were read.
Connection/package metadata only was inspected before synthetic QA. Synthetic
native conversion evidence does not validate a carrier/default messaging app.
Existing financial records are not rewritten by inference fixes. Historical
suppression, persisted lifecycle errors and purged messages require separately
grounded recovery; a future fix must not claim they were automatically repaired.

GitNexus refreshed at baseline: 9,131 nodes, 21,375 edges, 416 flows. Global
inventory omits 1,092 candidate entrypoints, 1,459 callees and 35 walks. The MCP
server retained an older cached index; fresh local CLI analysis plus source
review corroborates callers. Capture paths are HIGH risk; categorizer and date
parser reach CRITICAL risk. UNKNOWN/native framework/provider edges require
source corroboration. Final changed-symbol and test evidence will be recorded
after implementation; audits alone do not satisfy acceptance.
