# T-177a capture provenance and synthetic replay

Status: bounded source/document reconciliation complete and independently
reviewed, 2026-10-03. The overall T-177a holdout and device gates remain open.
This report records source inspection and a synthetic provider integration
test. It is not a device capture audit or an accuracy baseline from user data.
No phone, emulator, private SMS, network service, or paid model was used.
The 2026-09-30 path matrix was accurate for that source revision; commit
`f730857` added merchant resolution to history and resume on 2026-10-02. This
report supersedes that matrix with current wiring rather than revising the
historical observation.

## Capture path matrix

| Path | Active wiring | Meaningful differences |
|---|---|---|
| Live receiver | `smsCaptureBootstrapProvider` in `lib/capture/sms_ingestion.dart` builds `SmsIngestor` and subscribes to `CapturedSmsSource`; it watches `parserCascadeProvider`, `categorizerProvider`, and `messageKindClassifierProvider`. | The parser cascade tries template and generic parsing, then the optional on-device LLM field locator. `MerchantResolver` runs before categorization and permits similarity suggestions for nonduplicate rows. The platform runtime follows the `AppConstants.enableLocalLlm` default when supported and a model is available; `llmRuntimeProvider` does not read the persisted `enable_local_llm` feature flag. Status uses policy unless a lifecycle, duplicate, merchant-review, or fixed-status path selects it first. If an async provider is not ready, the subscription waits for provider rebuild. |
| Initial history | `smsHistoryImportRunnerProvider` in `lib/capture/sms_backfill.dart` awaits the template matcher, categorizer, and message-kind classifier, creates a template+generic parser, then passes inbox pages to `SmsIngestor.ingestBatch`. | It omits the LLM field locator, but runs `MerchantResolver` with `allowSuggestions: false`, so it skips new embedding-similarity searches; a previously stored learned/similarity alias can still request review. It seeds known transaction IDs and sets `fixedStatus: needsReview` with `fixed_review` mode. The native inbox is newest-first; page and message order is not a chronological learning order. |
| Resume catch-up | `smsIncrementalCatchUpProvider` builds the same template+generic parser and awaits the same categorizer/classifier. `smsIncrementalCatchUpBootstrapProvider` invokes its runner on startup and app resume. | It omits the LLM field locator and likewise skips new embedding-similarity searches while allowing a stored learned/similarity alias to request review. It sets `fixedStatus: needsReview` with `fixed_review` mode and scans a bounded page overlap around the known-SMS boundary. It is a recovery path, not a complete history replay. |

The test `test/capture/capture_provenance_replay_test.dart` exercises the live
bootstrap, history importer, and resume catch-up runner with the same synthetic
messages and injected local dependencies. It asserts that all three paths
categorize the same three parsed rows, resolve each synthetic merchant as a
new merchant with source `new`, retain the unrecognized fourth message without
creating a transaction, and persist the expected mode. It does not exercise
existing exact-name, user-alias, or legacy-alias matches. In this fixture the
rule-hit row is `needs_review`, and
history/resume non-rule rows are also `needs_review`. It does not exercise all
rule-policy outcomes: settled duplicate rows take a direct `auto` branch,
subject to later source-evidence write guards; rule hits may preserve eligible
`auto` or clamp `asked` to `needs_review` in fixed-review mode. Separate tests
cover the live rule-backed auto case (`decision policy keeps rule-backed high
confidence txn auto`) and the history/resume asked clamps (`history rule hit
clamps asked to review with fixed-review provenance` and `resume rule hit
clamps asked to review with fixed-review provenance`). The fixture injects a
template+generic parser for all modes and a no-op embedder; it does not
exercise the live LLM locator/runtime, a classifier model, network request, or
real inbox.

Current code persists the supported `capture-decision-v2` contract marker in
`confidence_json`, with `status_mode` set to `policy` for live capture and
`fixed_review` for history/resume. The earlier v1 marker was written by the
then-current code and is not retroactively reclassified: the v2 reader treats
v1, malformed, and unsupported markers as unknown; no rows are backfilled or
counted as current-version evidence. The version applies to the category and
initial-status decision, including its guards; the parser version remains
separate. [ADR 0018](../decisions/0018-capture-decision-version.md) defines
compatibility. The synthetic fixture reads v2 through the shared contract and
asserts both modes. The three parsed rows have the marker; the unrecognized
message has no transaction and remains unversioned.

## Provenance matrix

| Field or decision | Persisted evidence today | Current gap / interpretation |
|---|---|---|
| Amount, direction, channel, account/ref, parser time | Transaction columns; `evidence_json` contains field spans when the parser supplies them. | Parse success alone is not source proof. Missing evidence spans stay missing; the synthetic replay counts a non-transaction parse as uncovered. |
| Parser | `confidence_json.parser` stores confidence, parser source, template ID, and template provenance when available; `raw_sms` keeps parser version and processing outcome until retention expiry. | This does not version the downstream categorizer/status decision. Raw SMS retention is not extended for evaluation. |
| Source currency | `currency_code` and `currency_symbol` are stored separately from the parsed amount. | A symbol such as `$` without an ISO code remains ambiguous; no conversion is inferred. |
| Merchant identity | `merchant_raw`, `merchant_id`, and the `confidence_json.merchant` value/confidence/source. | All three paths call `MerchantResolver`. History/resume skip new embedding-similarity searches but retain exact/user/legacy resolution and deterministic new-merchant handling; a previously stored learned/similarity alias can still request review. Fuzzy suggestions do not assign identity. |
| Category | `category_id`; `confidence_json.category` records confidence/source and a rule ID when applicable. `Categorizer` supports rules, optional merchant memory, optional local classifier, seed map, P2P default, optional LLM suggestion, then fallback. | Production `categorizerProvider` wires rules, seed map, `LocalClassifier`, and adaptive threshold only. Merchant-memory and category-LLM callbacks are not wired into capture. The live parser has a separate optional field-locator LLM; history/resume omit it. |
| Transaction status | `transactions.status`; `confidence_json.capture_decision` identifies v2 and whether mode is `policy` (live) or `fixed_review` (history/resume). | The marker versions behavior, not correctness. Settled duplicate rows take a direct `auto` branch before source-evidence write guards; unsettled rows still require review. Rule paths use status policy and fixed-review clamps `asked` to `needs_review`. `auto` is not a user label. The current reader returns no supported version for legacy/unsupported markers; v1 rows retain that marker but are excluded from v2 evidence, while absent markers are unversioned. |
| User category decision | Versioned feedback links an explicit confirmation/correction to the prediction provenance used by the adaptive threshold safeguard. | Only explicit confirmation or correction can label an outcome. Silent predictions, status-only changes, and parser-only confirmation are excluded. |
| Preview version and deferral | Not part of the capture transaction record. | This milestone adds neither field. Scoped preview/replay and persistent deferral are separate T-177c/T-177d contracts; any schema addition requires an ADR and backup/deletion review. |

## Replay report contract

`test/support/capture_replay_report.dart` accepts normalized outcomes and an
independent label source, never raw SMS. It sorts by UTC receive time and then
SMS ID, rejects duplicate IDs, and groups cohorts by UTC month. Its denominators
are explicit:

- Precision numerator: predictions matching an explicit confirmation/correction.
- Precision denominator: predictions with an explicit confirmation/correction.
- Decision coverage: all predicted rows divided by all captured rows.
- Explicit-label coverage: labeled rows with a prediction divided by all
  explicit-label rows.
- User decisions per 100 rows: explicit confirmations/corrections divided by
  all captured rows, multiplied by 100.

No explicit labels yields `precision: null`, not a zero score. Unreviewed
predictions are reported as excluded. `isHoldoutValidated` is always false:
selected user feedback is a biased sample and the measured fraction must not be
presented as population precision. Missing source spans and absent decision
versions are counted separately; they keep `evidenceComplete` false.

The 4-row synthetic fixture produces 2 explicit labels, 3 predictions, 2
evaluated outcomes (1 correct, 1 incorrect and corrected), 1 excluded
unreviewed prediction, and 1 unparsed/unpredicted row. Its three persisted
transactions carry the current decision version; the unparsed row does not.
On that selected synthetic sample only,
precision is 1/2, decision coverage 3/4, explicit-label coverage 2/2, and user
decisions 50 per 100 rows. One row lacks a persisted decision version and the
unparsed row lacks field spans, so evidence is incomplete. These figures verify
report arithmetic only; they are not a baseline, holdout, or rollout gate.

This is local test/evaluation tooling, not a user-facing feature or production
historical-data reader. Generating a real baseline still needs a consented,
chronological, explicitly labeled holdout with source retention and cohort
selection documented. Keep inference suggestion-only until those measurements
and physical device capture coverage exist.

## T-140 and T-143 reconciliation

T-140 is historical component work. Its task pointer explicitly leaves current
provider integration gaps under T-177a/b; it does not establish that merchant
memory or LLM category suggestions are active. The production capture
categorizer provider currently supplies neither callback.

T-143a–c, including c1–c3, are verified complete as component tooling in
[`T-143`](../tasks/T-143.md). The runner, deterministic diff, and developer
metrics screen exist, but production capture has no call or scheduler for
`ShadowPipelineRunner`; the screen reads existing shadow rows and does not
start a run. A diff cannot provide accuracy without explicit labels. The
fixture above does not run shadow mode or write production rows. Production
shadow scheduling/isolation remains a T-177f release prerequisite, not an
unfinished T-143c1 task.

## Open gates

- Collect a real local-only, chronological holdout with explicit user labels;
  report counts before any precision claim.
- Complete physical device capture coverage, including the app-resume lifecycle
  and known-SMS-boundary behavior that the synthetic catch-up runner does not
  exercise.
- Record supported-device evidence for live delivery and resume catch-up.
- The owner must choose the consented chronological period and approve or
  revise the proposed cohort/metric thresholds before labels are opened or a
  holdout contract is frozen. No period has been selected and no thresholds
  have owner approval.
- Complete production shadow isolation/scheduling review before any T-177f
  staged release; existing T-143 tooling does not imply capture runs in shadow
  mode.

Historical contract verification at the time of the earlier milestone:
focused provenance/ingest/backfill tests 57/57, full Flutter suite 942/942,
and `flutter analyze --no-pub` clean. The 2026-10-03 documentation slice
passed focused capture/provenance tests 67/67, checked 140 Markdown files for
links, and passed `git diff --check`. GitNexus reported 8 files, 29 symbols,
0 affected flows, LOW risk, with no partial/truncated result notice. The full
application suite and analyzer were not rerun for this prose-only slice. The
supported marker is v2; old, malformed, and unsupported markers remain
excluded from current-version evidence. The proposed holdout period and
thresholds remain owner decisions.

The bounded source/document reconciliation is complete. Overall T-177a stays
open for owner selection of a consented chronological period, approval or
revision of proposed thresholds, the real holdout, and physical live/resume
capture evidence.
