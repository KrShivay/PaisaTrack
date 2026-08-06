# PaisaTrack product-value review — 2026-08-01

Scope: LUNA-07 and T-172a–g. This is an evidence register, not a claim that
unrun participant sessions or device acceptance have passed. Overall status:
**CLOSED WITH WAIVER**: the product owner recorded on 2026-08-01 that
participant and interactive accessibility evidence is not required for this
review. Evidence labels:

- **Source** — direct source/schema/UI inspection.
- **Test** — an existing automated test covers the behavior.
- **Corpus** — the synthetic review corpus at
  `test/fixtures/product_review/corpus.json` has an explicit expected contract;
  corpus-specific runtime execution is still a follow-up unless marked Test.
- **Human** — requires moderated participant or physical-device evidence.

## Decision summary

PaisaTrack’s product value is “turn noisy financial evidence into a trustworthy,
correctable local view of spending.” The review therefore ranks trust and
recoverability ahead of new intelligence:

1. Make the entire history findable and every headline number explainable.
2. Make capture failures observable without retaining message content.
3. Make correction, review, and deletion safe and reversible where practical.
4. Only then expand income, recurring, budgets, and narrative insights.

The current app already has broad capability coverage: four root destinations,
SMS capture/backfill, transaction detail/correction, manual entry, dashboard
metrics, trends/insights, recurring-series management, Ask, notifications,
encrypted backup/import, developer export, and local data controls. The critical
gap is confidence: several surfaces are feature-complete enough to look useful
before their completeness and data-quality state is visible.

## T-172a — capability inventory

| Capability / user job | Entry point | Data + rules | States / privacy | Evidence and current gap |
|---|---|---|---|---|
| First-run setup and SMS permission | `OnboardingScreen`; Settings recovery | Permission gate, backfill marker, local DB; continue without SMS is allowed | Granted, denied, permanently denied, import progress; permission and raw SMS are sensitive | **Source/Test** `lib/features/onboarding/onboarding_screen.dart`; permission recovery tests exist. Recheck-on-resume and complete status evidence remain open. |
| Live SMS capture | App bootstrap after permission | Android source → parser cascade → categorizer/merchant resolver → `raw_sms` and `transactions`; duplicate and lifecycle rules | Unsupported/paused senders should be reason-only; raw SMS has bounded retention | **Source/Test** `lib/capture/sms_ingestion.dart`, capture tests. Live failures are intentionally swallowed and need durable counters. |
| Historical SMS backfill and catch-up | Onboarding, Activity scan, resume | Paged native inbox, cursor, known-row boundary, parser/categorizer, idempotent transaction writes | Loading, partial failure, skipped/completed; no raw body in progress model | **Source/Test** `lib/capture/sms_backfill.dart`, backfill tests. Native reject counts, retry reasons, and cancellation/checkpoint UX are incomplete. |
| Activity history | Activity tab | `TransactionRepository.watchTransactionPage`; `(ts,id)` cursor; filters for direction, source, review, recurring and search | Loading, error/retry, empty, filtered empty; rows exclude deleted/duplicate-suppressed by default | **Source/Test** `lib/features/transactions/transactions_screen.dart`, `T-160a` tests. Search/filter still operate on the loaded window; T-160b/c/d remain required. |
| Transaction detail and source evidence | Activity row | Transaction, category, merchant, evidence spans, source SMS/VPA, lifecycle and exclusion flags | Detail, missing source, correction sheet; SMS body is sensitive and must be user-requested | **Source/Test** detail/evidence/correction tests. Correction + undo logic is duplicated across flows; source disclosure needs explicit retention wording. |
| Correct parse/category and undo | Detail, Sort, correction sheets | User correction, rule scope, evidence-preserving original fields, undo token | Save, failure, undo, correction scope preview | **Source/Test** repository and correction tests. Shared controller and characterization coverage are T-159/T-157 follow-ons. |
| Manual transaction entry | Activity action / empty state | Manual transaction repository insert, category and date, no SMS dependency | Validation, saving, save error, success | **Source/Test** `manual_entry_screen.dart` and tests. Needs parity with statement/SMS provenance and accessible form QA. |
| Dashboard “can I spend?” | Home tab | Dashboard aggregates, financial-calendar boundaries, settled-spend eligibility, budget baseline, recent rows | Loading, error, period selection, empty/partial data | **Source/Test** dashboard providers/widgets/tests. Existing review found a risky fallback from failed aggregate state to the newest loaded rows; this is P0 trust work. |
| Dashboard categories and budget prototype | Home cards | Category breakdown, monthly baseline, payment-source inclusion, shared eligibility | Empty categories, over/under budget, excluded source explanation | **Source/Test** dashboard tests. This is not T-098 category budgeting; per-category/month targets are absent. |
| Trends and deterministic insights | Trends tab | Insights table, burn-rate/anomaly/recurring calculations, financial eligibility | Loading/error/empty, insight cards, recurring link to Activity | **Source/Test** `InsightsEngine`, `InsightsScreen`, insight tests. Eligibility parity and “why this insight exists” need a visible contract. |
| Recurring series and expected events | Linked from Trends / recurring UI | `recurring_series`, `expected_events`, transaction reconciliation; active/missed/price-changed/settled states | Empty, error, status filters, cancel/reactivate, view transactions | **Source/Test** recurring tests. Calendar, reminder, and explainable ineligibility are not yet a complete user job. |
| Ask PaisaTrack | Ask orb in root shell | Local intent classifier/validator/query engine; deterministic renderer; no cloud runtime | Model missing, thinking, no answer, answer, unsupported intent | **Source/Test** assistant tests. Must show data window, eligibility, and confidence for numeric answers; never imply a complete result when query is bounded. |
| Ask Now notification and review queue | Android notification, Sort | Review queue, daily budget, shown IDs, category suggestions | Permission/notification unavailable, shown, corrected, dismissed | **Source/Test** notification tests. Notification state is not clearly part of data reset/backup disclosure. |
| Category management | Settings | Categories, seed map, correction rules | Add/edit/icon, invalid input, empty | **Source/Test** category manager tests. Needs an explicit effect preview for historical relabeling. |
| Payee labels and merchant identity | Settings | Merchants, aliases, rules, merge/backfill preview | Loading, preview, apply, conflict/error | **Source/Test** payee-label tests. Merge/delete semantics and rollback need product wording. |
| Payment-source management | Settings / filters | Payment sources and analytics inclusion | Add/edit/delete/toggle inclusion | **Source/Test** repository tests. Inclusion changes need an immediate total-impact explanation. |
| Encrypted backup/import | Settings | Encrypted archive of domain rows through document gateway; migration compatibility | Picker cancel, wrong passphrase, invalid/oversized/legacy payload, round-trip | **Source/Test** backup tests. Raw-SMS expiry/backup exclusion and bounded streaming remain T-127/T-170b. |
| Transaction export | Developer diagnostics | CSV and JSON export; explicit destination and confirmation | Cancel, success, failure; JSON is plaintext and sensitive | **Source/Test** export tests. Not a finished general-user export surface; add a privacy/data-footprint contract before promotion. |
| Delete/reset and recovery | Settings, startup recovery | Database reset, key-loss and startup-error routes | Confirm, cancel, failure, fresh DB; recovery must not silently replace a key | **Source/Test** reset/recovery tests. Native notification/model/cache state and backup/raw-SMS erasure boundaries need proof. |
| Local privacy/data footprint | Settings copy, source view | On-device DB, SQLCipher, raw SMS retention, local model, export/backup | Disclosure, source view, deletion | **Source** `docs/privacy.md`, ADRs. No dedicated footprint screen; T-169b is the implementation brief. |
| Developer capture/model diagnostics | Dev-only routes | Unparsed SMS reason counts, template trust, model metrics | Empty/error, export/sanitize fixture | **Source/Test** developer tests. Counts must stay content-free and must not become an accidental user-facing data leak. |

### Schema inventory

The current data layer includes `transactions`, `raw_sms`, `categories`,
`merchants`, `merchant_aliases`, `payment_sources`, `rules`,
`transaction_links`, `recurring_series`, `expected_events`, `insights`,
`baselines`, `feature_flags`, `feedback`, and `model_meta`. Important positives
are preserved evidence, lifecycle state, duplicate links, owned-transfer links,
and additive migrations. Not present as a complete user capability: accounts,
statement import/reconciliation, per-category budgets, salary-source review,
multi-transaction splits, and a user-facing data-footprint screen.

## T-172b — sanitized corpus and capability execution

The corpus is intentionally synthetic and local-only. It covers sparse,
typical, noisy, long-history, salary, transfers, refunds, pending/reversed,
and multi-source cases, including identical timestamps and a safe rejected
sender. It contains no real financial content. The expected contracts include:

- settled debit total and explicit excluded IDs;
- salary versus non-salary credits;
- refund/reimbursement/owned-transfer relationships;
- cursor order `(ts DESC, id DESC)`;
- lifecycle visibility and review eligibility;
- safe reason-only handling for unsupported senders; and
- export/delete assertions.

### Execution register

| Capability family | Corpus assertion | Current result | Confidence / next run |
|---|---|---|---|
| Ordering and history | Same timestamp has deterministic id tie-break; 125 rows have no gap/duplicate across pages | Cursor contract is present in T-160a; full keyset execution is T-160b | **Test + Corpus** repository test with 1k rows is required |
| Spending totals | Transfers, excluded card bill, pending, reversed, failed and duplicate echo do not alter settled debit total | Shared eligibility contract exists; dashboard fallback risk remains | **Test + Corpus** add a corpus-seeded aggregate parity test |
| Salary | Only `txn_salary_01` is a salary credit | No explicit salary analytics card/source correction surface exists | **Corpus** implementation required under T-166a/b |
| Refunds/reimbursements | Links remain visible; net effect is explained and source rows are not deleted | Link schema and parser tests exist; full UI flow is not complete | **Test + Human** add relationship UI acceptance |
| Pending/reversed/failed | Each lifecycle state is visible and excluded/explained correctly | Lifecycle routing tests exist; cross-surface explanation is incomplete | **Test** add Activity/detail/dashboard parity assertions |
| SMS capture | Salary parses as credit + salary; unsupported sender yields reason-only record | Sanitized SMS fixture system exists; capture counters/retry provenance are incomplete | **Test + Corpus** add the corpus matrix to fixture-contract tests |
| Review/correction | Low-trust row is reviewable, correctable, and undoable | Review and correction tests exist; controller duplication remains | **Test + Human** run Sort/detail scenarios |
| Recurring/expected | Active, missed, and price-changed states remain distinguishable | Recurring repository/UI tests exist | **Test + Corpus** add expected-event reconciliation cases |
| Backup/export/delete | Round-trip preserves domain rows; plaintext export is explicit; reset removes all in-scope rows | Backup/reset/export tests exist | **Test + Human** verify device files, notification state, model cache and raw-SMS expiry |
| Accessibility/responsiveness | Every primary action remains labelled, selected, ≥48dp, and visible at narrow/large-text/keyboard states | Some semantics/responsive tests exist; full matrix is open | **Human** device/TalkBack pass required |

“Current result” is deliberately not upgraded to “pass” when the corpus has an
expected contract but no corpus-specific runtime harness. The next engineering
step is to seed this JSON into repository/widget test helpers rather than copy
the rows into unrelated tests.

## T-172c — user jobs and comparable-product research

### User-job hypotheses to validate

These are hypotheses derived from the product contract and the requested
scenarios, not participant findings:

| Job | Success from the user’s perspective | Trust failure to watch |
|---|---|---|
| “Know what actually happened” | Find a transaction from any month and see source, date, status, and why it counts | Search says empty because only the current page was loaded |
| “Know what I can safely spend” | See a period total with completeness, exclusions, and a useful next action | Failed aggregate silently shows a plausible partial total |
| “Get my income right” | Salary is separated from transfers, refunds, and cashback | Credit is mislabelled or missing without explanation |
| “Fix the app without losing evidence” | Correct category/parse, preview scope, undo, retain original evidence | Correction mutates source or affects more history than expected |
| “Recover from noisy capture” | See counts/reasons and retry what is safe without reading raw messages | Capture silently drops rows or exposes personal SMS content |
| “Control my footprint” | Understand retention, backup inclusion, export, and deletion boundaries | Reset appears complete while native/model artifacts remain |

### Comparable patterns and transferability

| Product / standard | Observed public pattern | Transferable locally | Do not copy blindly |
|---|---|---|---|
| [YNAB features](https://www.ynab.com/features) and [reports](https://www.ynab.com/blog/ynab-reports-and-data) | Goals/targets, spending and net-worth reports, category breakdowns, income-v-expense views | Explicit goals, period comparisons, category drill-down, income-v-expense separation | Cloud bank sync, multi-device synchronization, and subscription assumptions conflict with PaisaTrack’s core local-first boundary |
| [Monarch recurring](https://www.monarch.com/track-recurring-bills-and-subscriptions) | Recurring calendar, paid confirmation, grouping/filtering, expected reminders, manual scan | Separate expected events from settled transactions; explain cadence and price changes | Push/email reminders and bank-fed completeness require a stronger local scheduler and permission contract |
| [Wallet by BudgetBakers features](https://budgetbakers.com/en/products/wallet/features/) | Category budgets, overspending alerts, automatic categorization, spending trends, bank synchronization | Per-category limits, visible threshold state, explainable trends, manual correction | Bank aggregator/cloud processing is outside the privacy fit; avoid implying comparable coverage without account sync |
| [WCAG 2.2 target size](https://www.w3.org/TR/WCAG22/) | AA target-size minimum is 24×24 CSS px with exceptions | Use as a baseline for spacing and focus behavior | Android native guidance is stricter for this product’s touch UI |
| [Android accessibility guidance](https://developer.android.com/guide/topics/ui/accessibility/views/apps-views) | Recommend at least 48dp focus/touch area and a description for each interactive element | Make 48dp exposed/tappable area, labels, selected state, and TalkBack order acceptance criteria | A passing static size check is not proof that a task is usable; run task-based device QA |

The evidence supports a “trustworthy local ledger” position rather than feature
parity with cloud aggregators. A local-first app should win on evidence,
disclosure, correction, and deletion—not on synchronized account count.

## T-172d — decision matrix

Scores are 1 (low) to 5 (high); effort is inverse value (5 = expensive). Risk
is trust/data-quality risk. The success metric is analytics-free and locally
verifiable.

| Opportunity | Value | Risk | Privacy fit | Reach | Effort | A11y impact | Priority / success metric |
|---|---:|---:|---:|---:|---:|---:|---|
| Full-history keyset search/filter and timestamp contract | 5 | 5 | 5 | 5 | 3 | 4 | **P0**: 100% of corpus records reachable once; zero duplicate/gap page transitions |
| Truthful aggregate loading/error/completeness state | 5 | 5 | 5 | 5 | 3 | 3 | **P0**: no failed aggregate renders as a numeric success; every total exposes period and exclusions |
| Capture outcome counters, reason buckets, bounded retry | 5 | 5 | 5 | 4 | 4 | 3 | **P0**: every synthetic message has exactly one outcome; no body/identifier appears in logs or stored diagnostics |
| Lifecycle/duplicate/transfer/refund explanation across Activity, detail, totals | 5 | 5 | 5 | 5 | 4 | 4 | **P0**: every excluded corpus row has a stable user-readable reason |
| Complete reset/backup/raw-SMS/native-artifact contract | 5 | 5 | 5 | 4 | 4 | 3 | **P0**: post-reset audit finds zero in-scope rows/files and key-loss never silently rotates the key |
| Salary income card and correction flow | 4 | 4 | 5 | 4 | 3 | 3 | **P1**: salary credit is correct; transfer/refund/cashback never counted as salary |
| Accessibility and responsive primary-flow matrix | 4 | 4 | 5 | 5 | 3 | 5 | **P1**: all primary actions labelled, selected, ≥48dp and tappable at required viewports |
| Recurring calendar, missed/price-change explanation | 4 | 3 | 5 | 4 | 4 | 3 | **P1**: expected/settled/missed states reconcile with no duplicate event |
| Per-category monthly budget model | 4 | 3 | 5 | 4 | 4 | 3 | **P1**: budget totals equal shared eligibility and refund/reimbursement semantics |
| Data-footprint/privacy screen | 4 | 2 | 5 | 4 | 2 | 4 | **P1**: a new user can name retention, backup, export and deletion boundaries |
| Narrative AI expansion | 2 | 5 | 4 | 3 | 5 | 2 | **P2/defer** until numeric/query completeness is proven |
| Cloud sync, account aggregation, sharing | 3 | 5 | 1 | 3 | 5 | 2 | **Defer/reject** under ADR 0002 and local-first product direction |

## T-172e — moderated usability and manual QA package

No participant sessions were run in this repository-only pass. The product
owner waived participant and interactive accessibility evidence for T-172e, so
no further session is planned. The following script remains available for a
future re-opened review; results must be appended as anonymized task
metrics, never financial content. The session should use the synthetic corpus
above or a disposable seeded database.

### Non-destructive device evidence — 2026-08-01

Read-only ADB inspection found a wireless Motorola edge 50 pro running Android
16 (API 36), physical display 1220×2712, override density 382, and font scale
1.0. The PaisaTrack process was alive and `MainActivity` was reported as the
resumed app task. `READ_SMS` and `RECEIVE_SMS` were granted; `POST_NOTIFICATIONS`
was denied. An initial screenshot had an active system phone-call overlay, so
that pass did not interact with the app.

After the overlay cleared, a second non-destructive smoke run navigated only
the existing Home, Activity, Sort, and Trends tabs, captured temporary
screenshots, and restored Trends. The root tabs, Activity search/add/filter
affordances, Sort controls, and Trends cards/charts rendered at the target
display size. The persistent bottom navigation visibly covered lower content
on Activity, Home, and Trends; a `DEBUG` ribbon was also visible. No
transaction decision, edit, export, reset, delete, permission change,
notification action, or accessibility setting was touched. This is device
reachability and screen-smoke evidence only; it is not a task-success,
TalkBack, large-text, or accessibility pass.

### Operator QA record — not human evidence

| Check | Result | Evidence and limitation |
|---|---|---|
| Root-tab navigation | **Pass** | Home, Activity, Sort, and Trends opened on the target device; Trends was restored. No transaction decision or data write was made. |
| Activity → detail → back | **Pass** | An existing Activity row opened Transaction Detail, where category, correction, and source/provenance affordances rendered; the route was exited without saving. No timing or participant metric was captured. |
| Android accessibility tree | **Observation** | The current Trends tree reported 41 nodes, 18 non-empty `content-desc` attributes, 0 non-empty Android `text` attributes, and 1 resource ID. Android accessibility was disabled, so this is a static signal only, not a TalkBack pass. |
| Large text at font scale 1.3 | **Fail** | Lower content was covered by the persistent navigation on Home, Activity, and Trends; Sort remained legible. Font scale was restored to 1.0 afterward. |
| Release surface | **Fail** | A visible `DEBUG` ribbon remained on each inspected screen; this is not release-build evidence. |

The operator trace is a device smoke record, not a moderated participant
session. Import, salary identification, correction/undo, export, deletion,
TalkBack, and confusion/time measures were intentionally not run against the
live financial database. They remain open for a disposable seeded database or
participant session.

| Scenario | Task prompt | Measure | Pass condition |
|---|---|---|---|
| First import | Grant SMS access or continue without it; start import and explain what happened | Completion, time, confusion, permission recovery | Participant can name current permission/import state and next action |
| Find a transaction | Find the older synthetic “Housing” row and open its detail | Completion, time, search/page errors | Finds it without guessing that “empty” means missing data |
| Understand spending | Answer “what counted this month?” and inspect an excluded transfer | Correct answer, explanation requests | Can distinguish settled spend, transfer, pending, and refund |
| Identify salary | Find salary income and compare to cashback/transfer | Completion, misclassification | Salary is clearly separated and source is understandable |
| Correct an error | Correct the low-trust row, choose scope, undo it | Error rate, undo discoverability | Source evidence remains visible; undo restores prior state |
| Export/delete | Read privacy disclosure, export, then reset a disposable database | Time, hesitation, confidence | Can state what is retained/exported/deleted and verifies completion |
| Accessibility pass | Repeat Find/Correct using TalkBack or large text at narrow width | Focus order, labels, target misses | All primary actions have meaningful labels, selected state, and ≥48dp target |

Record only: scenario ID, success/failure, seconds, assistance count,
confusion-point code, accessibility observation, and optional verbatim UI copy.
Do not record amounts, merchant names, SMS bodies, identifiers, screenshots
with financial content, or participant identity. T-172e is **WAIVED / NOT
REQUIRED** for this review; this is not a claim that an unrun human session
passed.

## T-172f — approved findings converted into briefs

The following dependency-ordered briefs are the implementation queue. Each
brief requires local verification only; no analytics SDK or cloud service is
needed.

| Brief | Depends on | Scope / acceptance criteria | Test and docs evidence | Rollback / owner |
|---|---|---|---|---|
| PV-01 Complete history contract | T-160a | Ship `(ts,id)` keyset page, SQL filters/search, timestamp display contract; prove 1k mixed-date rows, same timestamps, deleted/duplicate rows, insert-between-pages | Repository/widget tests; update `docs/development.md`, product status | Revert provider/query migration; **Owner: data + Activity** |
| PV-02 Truthful numbers contract | T-126 | Make aggregate error/loading explicit; remove plausible partial fallback; show period, completeness, eligibility and exclusion explanation | Dashboard provider/widget regression + corpus aggregate parity; update architecture/status | Keep old aggregate provider behind flag until parity; **Owner: dashboard** |
| PV-03 Capture outcome ledger | T-161a–e | Count scanned/rejected/unknown/accepted/parsed/created/known/unparsed/failure; persist safe reason/version; bounded retry and user surface | Sanitized fixture matrix, failure injection, privacy grep/log audit; update privacy docs | Disable retry surface while preserving raw row retention policy; **Owner: capture** |
| PV-04 Integrity explanation | T-164c–e, T-135 | One explanation model for deleted, duplicate, transfer, pending, reversed, refund and excluded source across list/detail/totals | Repository, detail, dashboard and corpus tests; schema/architecture note if additive fields required | Keep explanation read-only and hide behind feature flag; **Owner: data + UI** |
| PV-05 Safe correction and recovery | T-159a, T-157b, T-170a/b | Shared correction+undo controller; key-loss fail-closed; reset/backup erasure audit including native/model artifacts | Characterization, fault injection, device backup/reset evidence; update privacy/manual QA | Revert controller only; retain old correction paths until parity; **Owner: corrections + privacy** |
| PV-06 Salary and income semantics | T-162a, T-166a/b | Salary evidence matrix, explicit income card, source correction/undo; never count transfers/refunds/cashback as salary | Fixture-contract and dashboard tests; update schema/product status | Keep income card off if evidence confidence is insufficient; **Owner: enrichment + dashboard** |
| PV-07 Accessible primary flows | T-167a–h | Shared 48dp/inset/semantics contract across root tabs, sheets and detail; large text, keyboard, landscape and TalkBack matrix | Widget/semantics/golden/device evidence; update development/manual QA docs | Revert individual screen migrations while contract remains opt-in; **Owner: UI** |
| PV-08 Data footprint and release review | T-169b, T-171a/b | User-facing retention/backup/export/delete disclosure; release checklist reruns corpus, scorecard, UI and manual QA | Local checklist artifact and prior-baseline comparison; update `docs/product-quality-review.md` | Disclosure-only can ship before optional visualization; **Owner: release + privacy** |

Deferred ideas are explicit: cloud sync/account aggregation, sharing, opaque
AI coaching, and a feature-parity race with bank-connected products. Revisit
only after PV-01–05 pass their trust metrics.

## T-172g — release cadence

The recurring operating procedure is in
[`docs/product-quality-review.md`](product-quality-review.md). It defines the
baseline artifact, corpus rerun, scorecard comparison, UI/manual QA matrix,
release-candidate gates, ownership, and rollback evidence. A release candidate
may claim product-value confidence for this review when the recorded
product-owner waiver is retained; the waiver does not relabel operator smoke
observations as human validation.

## Evidence limitations

- GitNexus process queries and symbol context were useful for discovery, but
  some deep graph calls returned a LadybugDB initialization error. Direct source
  and test inspection was used for those symbols.
- No TalkBack or moderated participant session was completed in this pass. A
  non-destructive ADB smoke run reached the wireless device, opened an
  Activity row and returned, and visited the root tabs without mutating data.
  The reversible large-text pass exposed bottom-navigation/content overlap on
  Home, Activity, and Trends; a visible `DEBUG` ribbon also remains.
- Public competitor pages describe their own products; they are observations,
  not proof of user demand. The product-owner waiver closes T-172e for this
  review without converting the operator smoke record into human evidence.
