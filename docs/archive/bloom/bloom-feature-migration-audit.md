# Archived — Bloom Feature Migration Audit

Status: superseded snapshot; unfinished work is normalized in `TASKS.md`

Audit date: 2026-07-26

Pre-redesign baseline: `7ac14b7` (`main`)

Bloom baseline: `45a3546` (`codex/bloom-redesign`)

## Purpose

The Bloom handoff redesigned ten primary views, but it was not a complete
product inventory. The redesign therefore must not be treated as permission to
remove an existing capability that was absent from the mockups.

This audit compares:

1. `design/design_handoff_paisatrack_redesign/README.md` and the primary HTML
   prototype;
2. the Flutter UI at pre-redesign commit `7ac14b7`;
3. the Flutter UI at Bloom commit `45a3546`;
4. the current repositories, providers, platform integrations, and tests.

The required outcome is a capability-preserving Bloom migration. Reuse the
existing repositories and domain behavior; restore or redesign their UI entry
points and regression coverage.

## Classification

| Class | Meaning |
| --- | --- |
| Regression | A user capability existed at `7ac14b7` but is absent or materially weaker in Bloom. |
| Handoff gap | The Bloom handoff requires the behavior, but the current implementation does not provide it. |
| Legacy surface | The feature remains reachable, but its screen/dialog was not migrated to Bloom. |
| Misleading state | The UI presents hardcoded or incorrect financial/device state as live data. |

Priorities:

- **P0** — data correctness, recovery, privacy, security, or a primary feature is
  blocked.
- **P1** — important capability or drill-down is missing, but the main app
  remains usable.
- **P2** — visual consistency, discoverability, accessibility, or secondary
  workflow completeness.

## Executive findings

- SMS capture and history import still exist below the UI:
  `SmsHistoryImportRunner.run` feeds `SmsIngestor.ingestBatch`, categorization,
  rules, and the same transaction store used by live capture. Bloom retained a
  re-import tile in Settings, but did not implement the handoff's Home empty
  state action, a clear post-onboarding lookup/recovery flow, or adequate error
  and result states. The feature is therefore present in code but effectively
  missing or hard to discover in normal use.
- Transaction detail lost the largest correctness surface: description editing,
  explicit correction scope, suggested-category confirmation, low-trust parse
  confirmation/fix, amount/direction/merchant correction, and most provenance.
- Activity lost advanced filters, full-field search, pagination, pull-to-refresh,
  multi-select, and bulk categorization.
- Sort lost list mode, search, bounded pagination, selection/bulk operations,
  merchant-group confirmation, skip, and classifier explanation.
- Trends no longer renders generated insights, anomaly explanations,
  suggestions, or persistent dismissals.
- Settings visually retained many rows, but actual local-model management was
  replaced by a static “Engine active” label. Backup passphrase confirmation
  and validation were weakened.
- Several current cards show fixture-like claims as if they were live:
  `Hey Shivay`, `Lighter week than usual`, a fallback six-day streak, a Blinkit
  increase/cap suggestion, a fixed ₹48,000 budget action, a fixed app version,
  and an always-active AI engine.
- Category management, payee labels, payment sources, manual entry, recovery,
  developer diagnostics, pickers, and passphrase dialogs remain mostly legacy
  Material surfaces. They need design migration, not deletion.

## Capability matrix

### Onboarding, SMS lookup, and recovery

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Request SMS permission | Present | Present | — | — | Keep. |
| Continue without SMS | Present | Present | — | — | Keep visible for denied and permanently denied states. |
| Permission lookup failure | Explicit error and retry | Error collapses into the denied presentation | Regression | P0 | Show an inline error with Retry; do not mislabel a platform failure as user denial. |
| Permanently denied recovery | Explains system Settings path | Copy exists; primary action delegates to `request()` | Partial | P1 | Verify the gate opens app settings and show a visible “Open Android settings” action. |
| Initial import progress | Live progress | Present, but total/count availability varies | Partial | P1 | Keep live processed/found/failed progress through navigation and resume. |
| Home “Import texts” empty action | Required by handoff | Missing | Handoff gap | P0 | Add “Find transactions from SMS” to the no-data Home state. |
| Post-onboarding SMS lookup/re-scan | Settings re-import existed | Buried in Settings; no dedicated result view | Regression | P0 | Add the SMS lookup sheet specified in the design addendum and expose it from Home, Activity empty state, and Settings. |
| Re-import preserves corrections | Present in runner contract and copy | Present | — | — | Preserve the existing `force: true` idempotent path and user edits. |
| Partial-failure recovery | Counts failures and advises re-import | Only a snackbar summary | Partial | P1 | Show a persistent result row and “Retry failed messages”; never require the user to remember a transient snackbar. |
| Unparsed financial SMS diagnostics | Debug-only screen | Present in Developer options | — | — | Keep debug-only. Do not turn this into a release raw-inbox browser. |
| Raw SMS privacy boundary | Raw evidence developer-gated before redesign | Detail label implies provenance, but release data rules are unclear | Partial | P0 | Release UI may show sanitized source metadata; raw sender/body/confidence JSON stay developer-gated. |

“SMS lookup” in this plan means asking Android to scan the permitted SMS inbox
for financial transactions and reporting the result. It does **not** mean
exposing a searchable copy of all personal messages.

### Home

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Settings entry | App-bar action | Streak chip opens Settings without a settings affordance | Partial | P1 | Keep the chip if desired, but add settings semantics/tooltip or a distinct settings action. |
| Period selection | Current/previous month, today, 7/30 days, month picker, custom range | Missing | Regression | P1 | Add a compact period chip and Bloom date/month sheets. |
| Category drill-down | Category row/ring opened filtered transactions | Missing | Regression | P1 | Make each category row open Activity with the category filter. |
| Merchant drill-down | Top merchant opened filtered transactions | Removed from Home | Regression | P1 | Keep drill-down in Trends and any merchant card. |
| “All” Activity action | Existing navigation and required by handoff | Visible callback is empty in `dashboard_screen.dart` | Handoff gap | P0 | Switch the shell to Activity and retain tab state. |
| Recent transaction detail | Present | Present as a sheet | — | — | Keep. |
| Review-queue action | Review summary was actionable | Unsorted row is not actionable | Regression | P1 | Tap opens Sort; provide a visible alternative to swipe. |
| Recurring preview | Next recurring items plus “View all” | Removed; Recurring is only under Trends | Regression | P1 | Add a compact commitment/next-due action or ensure the budget card opens Recurring. |
| True empty state | SMS explanation and manual-add action | “No transactions yet today”; no lookup/manual actions | Regression + handoff gap | P0 | Distinguish no database history from no activity today; offer SMS lookup and manual add. |
| Dynamic greeting/context | Data-oriented current-period UI | Hardcoded name and status sentence | Misleading state | P0 | Use a stored/local greeting or neutral copy and derive the subline from providers. |
| Streak | New Bloom requirement | Falls back to six days and is not visibly connected to a verified inbox-zero transition | Misleading state | P0 | Default to persisted zero, increment once per qualifying day, and test idempotence. |
| Budget setup/edit | New Bloom requirement | “Set ₹48k” writes a fixed value | Handoff gap + misleading state | P0 | Open a validated monthly-budget editor; never write a sample amount. |
| Insight action | New Bloom requirement | Hardcoded Blinkit claim and cap | Misleading state | P0 | Render only an actual `InsightsEngine` suggestion with its real merchant/value, otherwise hide the card. |

### Activity

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Merchant search | Present | Present | — | — | Keep real-time behavior. |
| Search account/channel/note/reference/status | Present through `TransactionFilters.matchesSearch` | Reduced to display name, note, and amount | Regression | P1 | Restore the shared full-field search contract. |
| Direction filters | All/Spent/Received | All/Expenses/Income/Transfers/Unsorted | Enhanced | — | Keep, with correct transfer semantics. |
| Advanced filters | Date, category, merchant, account, channel, amount, review, recurring, source, anomaly | Missing | Regression + handoff gap | P1 | Restore as Bloom chips plus an Advanced filters sheet. |
| Active removable filter chips | Present | Missing except the single selected mode | Regression | P1 | Show every applied filter and allow one-tap removal/reset. |
| Initial category/merchant route title and back behavior | Present | Filtering remains, but the shell presentation does not explain the locked filter | Partial | P1 | Render the initial filter as a removable chip and provide an exit. |
| Pull-to-refresh | Present | Missing | Regression | P1 | Restore. |
| Load older / bounded pagination | Present | Missing; list remains limited by its provider | Regression | P0 | Restore pagination or infinite scroll so old imported SMS transactions are reachable. |
| Multi-select | Long-press selection | Missing | Regression | P1 | Restore selection mode with visible Select action. |
| Bulk categorization | Present | Missing | Regression | P1 | Restore feedback-recording bulk category updates. |
| Apply-to-merchant rule | Required by handoff | Missing | Handoff gap | P1 | Preview affected count, write through `RuleRepository`, support undo. |
| Export action | Required by handoff; exporter exists as dev infrastructure | Missing from Activity | Handoff gap | P1 | Product decision required: user CSV export or encrypted-only. Never silently expose a debug plaintext export. |
| Error/retry | Explicit state | Async errors can appear as empty data | Regression | P0 | Restore inline error and Retry. |
| Empty-state recovery | Manual add and SMS explanation | Static empty text only | Regression | P1 | Offer manual add, SMS lookup, and clear filters as appropriate. |
| Swipe alternatives | Long-press/detail/category controls available | Row actions are primarily swipe | Partial | P1 | Add an overflow/action button for TalkBack, keyboard, and discoverability. |

### Sort

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Guided review | Present | Present as a swipe card | — | — | Keep. |
| Classifier guess/confidence/reason | Present | Removed from the card | Regression + handoff gap | P0 | Show proposed category, confidence, and why before “Keep”. |
| Confirm low-trust category | Present | Keep changes only status; explanation is absent | Partial | P0 | Preserve explicit confirmation feedback and training semantics. |
| Choose category | Present | Present | — | — | Keep. |
| Skip | Present/required by handoff | Missing | Handoff gap | P1 | Add Skip without mutating the item. Prevent an infinite two-item loop. |
| Alternative category chips | Required by handoff | Missing | Handoff gap | P1 | Show the top safe alternatives plus “Something else”. |
| List view | Present/required by handoff | Missing | Regression | P1 | Restore a grouped list toggle with state retention. |
| Search | Present in list view | Missing | Regression | P1 | Restore display-name/raw-merchant search. |
| Bounded pagination | Present | Missing | Regression | P0 | Allow every review item to be reached, not just the initial provider page. |
| Multi-select/select all filtered | Present | Missing | Regression | P1 | Restore with filtered-scope semantics. |
| Bulk confirm | Present | Missing | Regression | P1 | Restore atomic/isolated bulk action and result count. |
| Merchant-group confirm | Present | Missing | Regression | P1 | Preview and confirm all matching counterparty rows; write learning rule once. |
| Explicit gesture alternatives | Buttons existed | Only Change/Keep buttons; no Skip or list alternative | Partial | P1 | Provide all three labeled actions and TalkBack semantics. |
| Error/loading | Explicit before redesign | Empty queue can be mistaken for Inbox Zero | Regression | P0 | Do not show Inbox Zero until the provider successfully returns an empty list. |
| Completion action | Empty screen existed | No “Back home” action | Handoff gap | P2 | Add action and verified one-time streak update. |

### Trends and recurring

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Deterministic monthly report | Present | Basic six-month/MoM/category/merchant analytics present | — | — | Keep. |
| Period/month selection | Dashboard/insights supported scoped reporting | Missing from Trends | Regression + handoff gap | P1 | Add month chip and ensure all cards use the selected period. |
| Generated narrative insights | Present with deterministic fallback | Removed | Regression | P1 | Restore mapped to Bloom insight cards; never invent figures in UI code. |
| Suggestions and anomaly explanations | Present | Removed | Regression | P1 | Restore fact + consequence + optional action. |
| Dismiss insight persistently | Present | Removed | Regression | P2 | Restore persisted dismissal and accessible overflow action. |
| Category/merchant drill-down | Present from old analytics/dashboard | Rows are not tappable | Regression | P1 | Open filtered Activity. |
| Empty/error/loading states | Designed states existed | Empty sections silently disappear; provider errors are not surfaced | Regression | P1 | Define all standard states. |
| Recurring list | Present | Present | — | — | Keep. |
| Price-creep and missed badges | Present | Every row displays “Active” | Regression + misleading state | P0 | Render actual `status` and `amountTrend`; never label missed/inactive as Active. |
| Upcoming timeline and status separation | Present in compact form/required by handoff | Flat list only | Handoff gap | P1 | Separate next 14 days from subscription/series management. |
| Recurring drill-down | Present | Present | — | — | Keep, and encode the merchant filter visibly in Activity. |
| Adjust/cancel tracking | Required by handoff | Missing | Handoff gap | P1 | Add series management with reversible or confirmed semantics. |

### Ask PaisaTrack

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Ask free text | Present | Present | — | — | Keep. |
| Broad prompt catalogue | Categorized prompt tray | Reduced to four presets | Regression | P2 | Use rotating chips for the existing catalogue; keep a Browse questions sheet if needed. |
| Category prompt filtering | Present | Missing | Regression | P2 | Restore in Browse questions, not necessarily on the primary sheet. |
| Privacy reassurance | Explicit copy | Replaced by generic “Natural language financial search” | Regression + handoff gap | P1 | Show “On-device · no internet used” when true. |
| Model missing/download/progress/retry | Runtime supports typed states and model management | Missing from assistant presentation | Regression + handoff gap | P0 | Render unavailable, download, progress, failure, and retry states. |
| Follow-up/action chips | Required by handoff | Missing | Handoff gap | P2 | Render only controller-provided safe follow-ups/actions. |
| Structured answer visuals | Required by handoff | Plain text only | Handoff gap | P2 | Add small bars/verdict treatment from deterministic answer data. |
| Error specificity | Typed results available below UI | All failures become the same generic answer | Partial | P1 | Map typed unavailable/unsupported/no-answer outcomes without leaking exceptions. |
| Duplicate header | Not present | App bar and body both repeat mascot/title | Handoff gap | P2 | Keep one sheet header with close affordance. |

### Transaction detail and correction

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Detail and amount | Present | Present | — | — | Keep. |
| Description/note edit | Present and atomic with feedback | Controller is seeded but no field/save action is rendered | Regression | P0 | Restore editable note and atomic save. |
| Category correction | Present | Immediate category write with undo | Partial | P0 | Keep quick choice, but restore explicit scope before merchant-wide learning. |
| Correction scope | This transaction vs matching merchant past/future | Removed | Regression | P0 | Restore inline Bloom radio or a scope sheet with affected count. |
| Suggested category confirmation | Present | Removed | Regression | P0 | Restore Confirm/Fix for `needs_review`. |
| Low-trust parse confirmation | Present | Removed | Regression | P0 | Restore Confirm/Fix for generic/public-template/legacy low-trust parses. |
| Parse correction | Amount, direction, merchant | Removed | Regression | P0 | Restore validated correction sheet and atomic feedback write. |
| Core evidence | Direction, channel, account, balance, reference, VPA | Reduced to account plus channel/status in technical section | Regression | P0 | Restore progressive disclosure of every frozen transaction field. |
| Confidence trail | Parse, merchant, category source/confidence/rule | Reduced to parse percentage | Regression | P1 | Restore human explanation first; raw JSON only in developer mode. |
| Raw SMS developer evidence | Sender/body in debug only | Not shown | Partial | P1 | Restore only behind developer mode and retention availability. |
| Save feedback/error result | Explicit success/failure | Category action has no guarded error state | Regression | P0 | Disable while saving, surface sanitized failure, and retain user input. |

### Settings, backup, model management, and secondary screens

| Capability | Before redesign | Bloom state | Class | Priority | Required migration |
| --- | --- | --- | --- | --- | --- |
| Theme choice | Present | Present | — | — | Keep. |
| Show paise | New handoff requirement and persisted setting exists | No Settings control | Handoff gap | P1 | Add toggle wired to `setShowPaise`. |
| Monthly budget | Repository and dashboard use it | No Settings row/editor; Home writes fixed ₹48k | Handoff gap | P0 | Add validated editor with clear/unset option. |
| Categories | Present | Reachable, legacy surface | Legacy surface | P2 | Restyle as Bloom sheet/page without losing hierarchy/search/icon/merge behavior. |
| Payee labels | Present | Reachable, legacy surface | Legacy surface | P2 | Preserve search, unlabeled filter, merge preview/conflict handling. |
| Payment sources | Present | Reachable, legacy surface | Legacy surface | P2 | Preserve nickname, owned/active, analytics inclusion, and transfer explanation. |
| Local model status | Live status/runtime/backend/size | Static “Engine active” | Regression + misleading state | P0 | Restore live status. |
| Download/cancel/delete model | Present | Removed | Regression | P0 | Restore with progress, storage/support reasons, retry, and confirmation for delete. |
| Ask daily budget | Present | Present | — | — | Keep. |
| Backup export passphrase | Minimum length plus confirmation | Hint only; no field validation or confirmation | Regression | P0 | Restore form validation, confirmation, clear controllers on disposal, and sanitized errors. |
| Backup MIME/name | Octet-stream encrypted backup | Current UI suggests JSON name/MIME for encrypted bytes | Regression | P0 | Use the established encrypted filename and `application/octet-stream`. |
| Backup import | Present | Present | Partial | P1 | Preserve cancellation/result states and refresh dependent providers after success. |
| SMS history import | Present | Present but buried | Partial | P0 | Route to the dedicated lookup/recovery sheet. |
| Settings load error | Sanitized retry state | Displays `Error: $err` | Regression | P0 | Log internally and show a generic inline error with Retry. |
| Data reset | Confirmed irreversible reset | Still confirmed; handoff says undo for ten seconds | Spec conflict | P0 | Keep confirmation unless reset is redesigned as a genuinely recoverable delayed commit. Do not promise undo after key/database deletion. |
| App/version/model copy | Derived/live before redesign where applicable | Hardcoded version/privacy/model state | Misleading state | P0 | Read package/runtime state or omit the claims. |
| Manual entry | Present | Reachable in a Bloom sheet, inner form remains legacy | Legacy surface | P2 | Restyle while retaining validation, debit/credit, category, date, and save behavior. |
| Key-loss recovery | Present | Legacy surface | Legacy surface | P1 | Restyle without weakening explicit destructive confirmation. |
| Category/filter/correction sheets | Present | Mixed Bloom and legacy; correction sheet stranded | Legacy surface | P1 | Consolidate on `BloomSheetScaffold`; retain every field and return type. |
| Developer diagnostics | Present | Reachable in debug | Legacy surface | P2 | Restyle last; keep all privacy warnings and export guards. |

## Requirements by implementation workstream

### M0 — Remove misleading state

Before restoring secondary features, remove or derive every hardcoded claim that
can be mistaken for the user's financial or device state.

Acceptance:

- no sample user name, streak, merchant trend, budget, model status, or app
  version is presented as live;
- unavailable data produces a truthful empty/disabled state;
- every financial sentence is derived from a provider/repository result;
- widget tests use provider overrides rather than production fixture copy.

### M1 — Restore SMS lookup and recovery

Implement the SMS lookup sheet from
`docs/archive/bloom/bloom-feature-design-addendum.md`. Reuse
`SmsHistoryImportRunner`; do not fork ingestion or write transactions directly.

Acceptance:

- visible from Home with no history, Activity empty state, and
  Settings → Data & backup;
- handles unknown/denied/permanently-denied/granted permission states;
- reports processed, imported, skipped/duplicate, and failed counts where the
  platform/domain result exposes them;
- navigation away and app resume do not lose observable progress;
- re-scan preserves edits, manual entries, confirmations, and deletes;
- no raw SMS body, sender, prompt, or identifier is logged;
- device test covers a real inbox scan and a subsequent idempotent re-scan.

### M2 — Restore transaction correction integrity

Reintroduce the pre-redesign correction and feedback contracts inside the Bloom
detail sheet.

Acceptance:

- category, note, amount, direction, and merchant corrections use repository
  methods that write feedback atomically;
- category scope is explicit and previews the affected count;
- low-trust parse and suggested-category decisions have Confirm and Fix paths;
- failed writes retain edits and expose a sanitized retry;
- regression tests removed during redesign are restored or replaced with
  equivalent Bloom tests.

### M3 — Restore Activity and Sort scale workflows

Acceptance:

- advanced filters use `TransactionFilters`; do not create a second filter
  model;
- search again covers display name, raw merchant, account, channel, note,
  reference, and status;
- pagination makes all retained transactions/review items reachable;
- multi-select, bulk category, and merchant-group actions keep feedback/rule
  semantics;
- every swipe action has a visible button/menu alternative;
- loading, empty, filtered-empty, error, and retry are distinct.

### M4 — Restore analytics, recurring, and assistant intelligence

Acceptance:

- Trends consumes current deterministic/generated providers rather than
  hardcoded narrative copy;
- month selection scopes every Trends card consistently;
- category and merchant rows drill into Activity;
- recurring rows render actual expected/settled/missed/inactive/price-change
  state;
- assistant renders typed unavailable/download/error states and explicit local
  privacy copy;
- dismissals and one-tap actions are persisted and undoable when the underlying
  mutation is truly reversible.

### M5 — Complete Settings and legacy-surface migration

Acceptance:

- monthly budget, show paise, live model management, secure backup, SMS lookup,
  categories, labels, payment sources, and reset remain reachable;
- sub-screens share Bloom tokens and exit behavior but retain their feature
  contracts;
- package/model status is live;
- passphrase validation happens before export;
- irreversible reset retains confirmation until a real rollback design exists;
- all secondary screens define loading, empty, normal, error, retry, narrow,
  large-text, and reduced-motion behavior.

## Required regression suite

Restore behavioral coverage rather than only checking that Bloom labels render.
At minimum:

- onboarding permission error/retry and permanently denied recovery;
- Home SMS lookup, period selection, Activity/Sort/Recurring drill-downs, and
  data-derived copy;
- Activity full-field search, advanced filters, pagination, multi-select, bulk
  category, and filtered-route state;
- Sort list mode, search, pagination, skip, category choice, individual confirm,
  bulk confirm, merchant-group confirm, and provider error vs Inbox Zero;
- Trends generated/deterministic states, dismissals, month selection, and
  drill-downs;
- recurring missed/price-change/inactive rendering;
- assistant privacy, model unavailable/download/retry, suggestions, and send;
- transaction detail note/category/parse corrections, scope, feedback atomicity,
  frozen evidence, and debug-only raw SMS;
- Settings live model controls, theme/show-paise/budget persistence, secure
  backup validation, sanitized errors, SMS scan, and data reset;
- accessibility: TalkBack labels, 48×48 targets, large text, focus order,
  non-color status cues, reduced motion, and visible alternatives to gestures.

## Completion gate

The migration is complete only when:

1. every P0 and P1 row is implemented or explicitly deferred with owner,
   rationale, and replacement workflow;
2. each pre-redesign behavioral test removed during Bloom has an equivalent
   passing Bloom test or a documented product decision explaining its removal;
3. `flutter analyze --no-pub`, the full Flutter test suite, Android unit tests,
   and device acceptance for SMS/model/document-picker behavior pass;
4. GitNexus `detect_changes(scope: "compare", base_ref: "main")` shows only the
   intended symbols and flows;
5. no debug placeholder, sample financial claim, raw exception, or raw SMS
   disclosure remains in a release surface.
