# T-177a capture provenance and synthetic replay

Status: partial audit, 2026-09-30. This report records source inspection and a
synthetic provider integration test. It is not a device capture audit or an
accuracy baseline from user data. No phone, emulator, private SMS, network
service, or paid model was used.

## Capture path matrix

| Path | Active wiring | Meaningful differences |
|---|---|---|
| Live receiver | `smsCaptureBootstrapProvider` in `lib/capture/sms_ingestion.dart` builds `SmsIngestor` and subscribes to `CapturedSmsSource`; it watches `parserCascadeProvider`, `categorizerProvider`, and `messageKindClassifierProvider`. | Parser cascade can call the optional on-device LLM field locator after template and generic parsing. `MerchantResolver` runs before category prediction. Status is decided by `DecisionPolicy`, unless an earlier guard forces review. If any async provider is not ready, the subscription is not started until the provider rebuilds. |
| Initial history | `smsHistoryImportRunnerProvider` in `lib/capture/sms_backfill.dart` awaits the template matcher, categorizer, and message-kind classifier, creates a template+generic parser, then passes inbox pages to `SmsIngestor.ingestBatch`. | It omits the LLM field locator and merchant resolver, seeds known transaction IDs, and sets `fixedStatus: needsReview`. The native inbox is newest-first; page and message order is not a chronological learning order. |
| Resume catch-up | `smsIncrementalCatchUpProvider` builds the same template+generic parser and awaits the same categorizer/classifier. `smsIncrementalCatchUpBootstrapProvider` invokes its runner on startup and app resume. | It omits the LLM field locator and merchant resolver, sets `fixedStatus: needsReview`, and scans a bounded page overlap around the known-SMS boundary. It is a recovery path, not a complete history replay. |

The test `test/capture/capture_provenance_replay_test.dart` exercises each
provider with the same synthetic messages and injected local dependencies. It
asserts that all three paths categorize the same three parsed rows, that the
unrecognized fourth message is retained without creating a transaction, and
that history/resume force `needs_review`. It also pins the current identity
difference: live records merchant source `unembedded` from the resolver, while
history/resume retain parser merchant text with source `template`. The fixture
does not activate an LLM, classifier model, network request, or real inbox.

## Provenance matrix

| Field or decision | Persisted evidence today | Current gap / interpretation |
|---|---|---|
| Amount, direction, channel, account/ref, parser time | Transaction columns; `evidence_json` contains field spans when the parser supplies them. | Parse success alone is not source proof. Missing evidence spans stay missing; the synthetic replay counts a non-transaction parse as uncovered. |
| Parser | `confidence_json.parser` stores confidence, parser source, template ID, and template provenance when available; `raw_sms` keeps parser version and processing outcome until retention expiry. | This does not version the downstream categorizer/status decision. Raw SMS retention is not extended for evaluation. |
| Source currency | `currency_code` and `currency_symbol` are stored separately from the parsed amount. | A symbol such as `$` without an ISO code remains ambiguous; no conversion is inferred. |
| Merchant identity | `merchant_raw`, `merchant_id`, and the `confidence_json.merchant` value/confidence/source. | Live calls `MerchantResolver`; history and resume currently do not. No identity merge is inferred from the parser string. |
| Category | `category_id`; `confidence_json.category` records confidence/source and a rule ID when applicable. `Categorizer` runs rules, optional memory, optional local classifier, seed map, P2P default, optional LLM suggestion, then fallback. | `categorizerProvider` wires rules, seed map, `LocalClassifier`, and adaptive threshold; it supplies neither merchant-memory nor LLM-suggester callbacks. Helpers existing in source are not active production behavior. |
| Transaction status | `transactions.status`; live uses the decision policy, while history/resume force `needs_review`. | No persisted decision-policy version is present in the row. An `auto` status is not a user label and cannot be counted as correctness evidence. |
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
evaluated outcomes (1 correct, 1 incorrect and corrected), 1 excluded unreviewed prediction,
and 1 unparsed/unpredicted row. On that selected synthetic sample only,
precision is 1/2, decision coverage 3/4, explicit-label coverage 2/2, and user
decisions 50 per 100 rows. All four rows lack a persisted decision version and
the unparsed row lacks field spans, so evidence is incomplete. These figures
verify report arithmetic only; they are not a baseline, holdout, or rollout
gate.

This is local test/evaluation tooling, not a user-facing feature or production
historical-data reader. Generating a real baseline still needs a consented,
chronological, explicitly labeled holdout with source retention and cohort
selection documented. Keep inference suggestion-only until those measurements
and physical device capture coverage exist.

## T-140 and T-143 reconciliation

T-140 is historical component work. Its task pointer explicitly leaves current
provider integration gaps under T-177a/b; it does not establish that merchant
memory or LLM category suggestions are active.

T-143a–c provides feature flags, shadow storage/runner, disagreement diff, and
developer presentation. The production capture providers have no call to
`ShadowPipelineRunner`; the runner's result compares outputs and cannot provide
precision without explicit labels. The fixture above does not run shadow mode
or write production rows. T-143c1 remains on the board pending its status
reconciliation with the completed T-143a–c brief.

## Open gates

- Collect a real local-only, chronological holdout with explicit user labels;
  report counts before any precision claim.
- Add a capture-decision version to future provenance only after a separate
  design/review that defines migration, backup, and deletion behavior.
- Record supported-device evidence for live delivery and resume catch-up.
- Decide whether live/history/resume differences above are intended product
  behavior before changing any production wiring.
