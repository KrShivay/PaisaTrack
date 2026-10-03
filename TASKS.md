# Future Development Board

Only unfinished work belongs here. `docs/product-status.md` records current
state; Git history and `docs/archive/` retain completed evidence.

Priority: P0 release blocker, P1 high-impact, P2 important, P3 planned, P4/P5
later hardening.

## In Progress

## Ready

<!-- Groomed tasks awaiting an implementer; see docs/plans/roadmap.md for the
     proposed order of the remaining backlog. -->

## In Review

<!-- Implementations in review; retain each task's remaining acceptance gates. -->
- [ ] T-199 [P1] Show a scannable static UPI QR for stored transaction VPAs in details and Sort. Detail device QA on the earlier geometry build and normal/max-input decoder checks passed. The final same-version 0.1.8+2017 artifact is installed and hash-verified; no UI check was run on that exact build. Sort card/list QA remains open. See [T-199 brief](docs/tasks/T-199.md); QR dependency/payload decision: [ADR 0023](docs/decisions/0023-static-upi-qr.md).
- [ ] T-167j [P0] Implement the app-wide Android, predictive, and in-app back contract. Host behavior is implemented; see [T-167j brief](docs/tasks/T-167j.md) for test evidence and open device gates.
- [ ] T-176 [P1] Apply the global bottom-inset contract to all screens.
  - Acceptance: exercise Trends, Settings (including Not transactions), Ask,
    transaction detail, nested sheets, and floating actions through their real
    routes. Verify final rows and actions clear the floating navigation in
    gesture and three-button modes, and remain visible/tappable with the
    keyboard, compact/landscape viewports, and large text.
  - Verified acceptance slice: a route harness mounts the production
    `HomeFloatingNavPill`, `BloomBottomInset` adapter, and actual Trends route.
    The Trends final section clears the actual pill at 24dp gesture and 48dp
    three-button insets on 402×874, and at 568×320 landscape with 1.5× text.
    A separate bounded `HomeShell` route test now covers its actual pill and
    Ask modal. These earlier synthetic checks did not demonstrate a production
    inset gap; the later physical Ask test did, and the scoped route fix is
    recorded below.
  - Settings/Not transactions slice: five real-route checks open Settings,
    tap its Not transactions action, and assert the final synthetic history row
    clears the production navigation pill at 24dp/48dp insets on 402×874,
    320×568 at 2× text, and 568×320 at 1.5×/2× text. The inherited
    `MediaQuery.padding.bottom` gives the history `ListView` its bottom inset;
    no inset fix was needed. Tapping the row exposed and fixed a `setState`
    callback returning `_load()`'s Future, and the compact 2× layout exposed
    and fixed the trailing amount consuming the entire `ListTile` width. The
    test unmounts the route and closes its in-memory Drift database inside the
    test body so cleanup does not defer `StreamQueryStore.markAsClosed`'s
    `Timer.run` until Flutter's post-test teardown.
  - Ask compact-keyboard slice: the production full-screen Ask route now has
    a focused test at 320×568 and 2× text, then dynamically resizes to 320×348
    with zero residual inset to model a window-resize platform contract. The
    API 36 phone later reported a full-height app window plus a nonzero IME
    inset despite `adjustResize`; the synthetic resize case covers only that
    alternate contract and does not substitute for physical behavior. The
    compact Ask-only header keeps the composer visible,
    retains a 48dp close target, and leaves the transcript scrollable; normal
    height keeps the full header. The earlier 42px overflow figure came from
    a fixture that applied both the 348dp resize and a 220dp inset, double-
    counting the keyboard only in that test setup. A corrected route-size-only
    fixture still reproduced a compact-height issue: the
    full header title and subtitle wrapped to 138dp and 155dp, leaving only
    23dp for the AssistantScreen. A submitted user message now verifies the
    actual transcript ListView has positive scroll extent at 320×348/2× text;
    its prompt panel is capped to leave transcript space in 96–240dp content
    heights. The full-screen sheet helper adds opt-in keyboard avoidance for
    HomeShell → Ask; other full-screen callers retain their existing inset
    behavior.
  - Activity/detail/correction slice: three cases use the production
    `TransactionsScreen`, `HomeFloatingNavPill`, bottom-inset adapter, detail
    route, and nested correction sheet with synthetic provider data. At
    402×874/24dp/1× and 568×320/24dp/1.5× plus 568×320/48dp/2×, the Activity
    transaction row scrolls clear of the pill and remains tappable; the detail
    edit action opens the correction sheet and its direction choice remains
    tappable. No detail or sheet inset defect was demonstrated, so production
    code is unchanged. The test fixture keeps the route under a nested
    Navigator with the production pill/adapter because mounting `HomeShell`
    leaves Drift stream cleanup timers pending.
  - HomeShell/Ask integration slice: three tests open Ask through the
    production `HomeFloatingNavPill` and root modal route. At 402×874, the pill
    respects simulated 24dp gesture and 48dp three-button safe padding and the
    composer mounts. At 320×568/2× text, a full-window route with 220dp of
    `viewInsets` keeps the 48dp close target and composer within the 348dp
    visible area and preserves the inset for nested routes. The direct Ask
    route test separately covers a synthetic resize to 320×348 with zero
    residual inset. The focused fixture leaves the database unopened,
    explicitly unmounts the shell, and completes without a Drift teardown
    timer. The existing HomeShell Activity nested-Navigator test also passes
    in isolation. Physical keyboard behavior remains a device-only gate.
  - T-176 route-audit follow-up for T-167c: a trial through the real Sort
    detail caller exposed `WeeklyReviewScreen`'s card/action `Column` overflowing
    at 568×320 by 30dp with 1.5× text/24dp gesture inset and by 86dp with 2×
    text/48dp three-button inset. At 2× the card is outside the viewport, so
    this caller cannot reach detail. Existing Weekly Review widget tests use
    the default portrait viewport and do not cover compact landscape. Keep the
    layout fix in T-167c; no production review-screen change is part of T-176.
  - The synthetic Sort→detail route now passes after the T-167c responsive
    fix; physical-device QA remains pending. The phone was online for the
    unrelated 2026-09-30 v2011 release install/launch. Still open: Ask
    modal-route acceptance on a physical device and remaining compact/
    landscape combinations. The synthetic route tests used no emulator,
    inspected no private SMS/DB data, and changed no phone or APK state.
  - Physical QA on the exact published v0.1.3+2011 artifact from source
    `3b2fb6b` confirmed Ask composer occlusion by the IME in default portrait at
    1× and 1.5×, with repeated settled-IME metrics and local screenshots.
    No messages were entered or submitted; no suggestion was selected, and no
    transaction edits, SMS scan, permission, key, backup, reset, or restore
    operation was performed. Settings were restored. Physical acceptance
    failed and remains open; synthetic resize tests do not close it. Evidence:
    [T-176 physical Ask keyboard QA](docs/reports/T-176-physical-ask-ime-2026-09-30.md).
  - Merged Ask fix (`3d5f310`): the full-screen sheet helper now has opt-in keyboard
    avoidance, enabled only for HomeShell → Ask, preserving existing inset
    ownership for other callers. The Ask header selects compact layout from
    available route height after subtracting `viewInsets`; descendants retain
    the original `MediaQuery.viewInsets` for nested routes. Regression-first
    full-window/220dp-inset test failed before the fix with the composer bottom
    at 548dp (visible bottom 348dp). Direct Ask tests cover full-window plus
    inset and resized-window plus zero inset; a nested modal test verifies
    inset preservation. The production HomeShell route now covers both
    320×568/2× with a 220dp inset and a phone-like 434×964/1× viewport with a
    370dp inset; both cases clear the IME, close Ask, and return Home. Focused
    helper/Ask/HomeShell/category/detail suites passed 29/29; full Flutter
    suite 954/954; analyzer and formatter clean. This is synthetic
    verification; the implementation is in main. Physical verification on the
    reviewed 4012 build is recorded in
    [the 2026-10-01 install/Ask report](docs/reports/release-v2012-owner-phone-install-2026-10-01.md).
    Ask opened through the production pill and the empty composer remained
    above the real IME at 1×, 1.5×, and 2× portrait. At 2×, one safe scroll
    exposed a suggestion row above the keyboard; no suggestion was selected.
    The close target worked, the route returned Home, and settings were restored.
    Landscape, three-button navigation, other T-176 routes, and the broader
    T-167c matrix remain untested; both physical acceptance tasks remain open.
  - Focused verification: global bottom-inset route tests 11/11, including
    Activity/detail/correction at three viewports; Ask route plus
    AssistantScreen tests 9/9; production HomeShell→Ask route 3/3 and existing
    HomeShell Activity route 1/1; full Flutter suite 936/936; detail/Note and
    full-screen sheet baseline 17/17; `flutter analyze --no-pub`, formatter,
    diff check, and GitNexus detect-changes clean. No emulator, private
    SMS/DB data, phone mutation, or APK change.


- [ ] T-194 [P1] Measure installed storage and cold-start for the compressed
      ARM64 APK-size trial.
  - The signed v2011 candidate is on branch `codex/apk-size-trial` at commit
    `4a9fdfa`; it is 26,180,416 bytes with SHA-256
    `cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`.
    The release-only packaging config remains isolated on that branch and is
    not adopted on main.
  - Remaining acceptance: the supported ARM64 phone was online for the
    2026-09-30 published-release launch, but the compressed candidate has not
    been installed. T-194 still needs its separate physical candidate launch,
    installed-storage measurement, and cold-start comparison before adoption.
    No candidate APK publication is part of this task.
  - Details: [T-194](docs/tasks/T-194.md).

- [ ] T-177a [P1] Audit production integration, provenance, and baseline
      accuracy (bounded source/document reconciliation complete; owner holdout
      and device gates open).
  - Bounded milestone: add a local chronological replay/report contract and
    synthetic fixtures that exercise live, history, and resume provider wiring;
    document per-field provenance and deliberate path differences. Keep T-177a
    open for real-data holdout, device capture coverage, and rollout gates.
  - Active fix: unreviewed `auto` rows are not accuracy evidence and must never
    lower the persisted category threshold. Lowering requires an explicit
    user-confirmation feedback event with category-prediction provenance;
    corrections remain error evidence and may raise the threshold. Historical
    v1/v2 adaptive values are ignored so prior silent-row lowering cannot
    persist. Completed chronological 50-outcome cohorts are fingerprinted;
    changed outcomes replay those cohorts from the static default. If undo or
    category removal leaves fewer than 50 eligible outcomes, the learned value,
    count, and fingerprint are cleared.
  - Synthetic milestone adds live/history/resume provider fixtures, a
    chronological explicit-label report contract, and the provenance matrix in
    `docs/reports/T-177a-capture-provenance.md`. The 2026-10-03 source audit
    reconciles the report, ADR 0018, and T-143 component status: the supported
    marker is `capture-decision-v2`; all three capture paths resolve merchants,
    while history/resume skip new embedding searches (stored fuzzy aliases can
    still request review); category memory/LLM
    callbacks and production shadow scheduling are not wired. T-143c1–c3 are
    complete as tooling. The resume fixture calls the catch-up runner directly;
    app-resume lifecycle, known-SMS-boundary behavior, and physical live/resume
    capture remain unverified. The bounded source/document slice is complete
    and independently reviewed; T-177a remains In Review for owner holdout
    and device acceptance. No holdout period is selected and proposed cohort/
    metric thresholds await owner approval or revision. Real-data holdout and
    physical capture evidence remain pending. The supported phone's unrelated
    2026-09-30 v2011 release install/launch is not T-177a evidence.
  - Historical verification for the threshold-safeguard implementation:
    threshold tests 17/17; repository/detail/template-ledger
    tests 38/38; full Flutter suite 903/903; analyzer, changed-file formatting,
    and diff check clean. Same-count correction, v1/v2 state invalidation,
    multiple cohorts, undo to 49 outcomes, and full category removal are
    covered. GitNexus impact: `AdaptiveThresholdPolicy` HIGH (47 symbols / 4
    flows), `TransactionRepository` CRITICAL (80 / 43 direct), `TransactionDetail`
    CRITICAL (77 / 40 direct), `TransactionDetailScreen` HIGH (42 / 18 direct),
    `TemplateTrustLedger` HIGH (90 / 12 direct); exact ledger `refresh` is
    UNKNOWN with 2 dropped callers, text search corroborates call sites.
    Detect-changes reports 25 symbols, 9 files, 4 processes, MEDIUM. No schema,
    phone, or APK changes.
  - Historical capture-decision implementation verification: focused
    provenance/ingest/backfill tests 57/57; full Flutter suite 942/942;
    analyzer and diff check clean at that revision. These are not fresh checks
    for the 2026-10-03 documentation reconciliation; no full application suite
    is claimed for this prose-only slice. No schema migration, inference
    activation, accuracy claim, phone, or APK change.
  - Detail now has a separate evidence-backed parse-confirm action; it never
    changes transaction status/category and intentionally does not count as
    category-threshold evidence. Current source wiring and provenance are now
    documented; the real baseline, owner holdout, and physical device coverage
    remain open.

- [ ] T-167c [P1] Fix large-text overflows and cover primary transaction flows.
  - Acceptance: fix confirmed 320×568/2× overflow in HomeShell navigation,
    Activity header, and Trends header. Add narrow/wide viewport checks at
    1.5×/2× text for navigation, Activity/list and transaction entry/detail
    flows, and Trends. Preserve visible streak count and period context in
    compact Dashboard layouts, label Ask accessibly, and keep long foreign-
    currency amounts readable. Preserve visible navigation, accessible labels,
    and minimum 48dp tap targets.
  - Scope: flexible/wrapping/adaptive layout fixes only; no device mutation.
  - T-176 route-audit follow-up: fixed `WeeklyReviewScreen`'s confirmed
    30dp/86dp compact-landscape overflows. The production Sort card scrolls
    vertically at 568×320 with 1.5×/24dp and 2×/48dp settings while preserving
    the configured text scale; the action row clears the production pill. A real
    synthetic Sort→detail route test verifies vertical finger scrolling reaches
    the title's top and bottom, taps the visible card intersection to open the
    production detail sheet, and taps Skip to advance to the next synthetic
    item. Standard portrait coverage stays in the same route suite.
  - Verification: responsive route suite 42/42; focused changed-screen/inset
    suite 56/56; reviewer follow-up focused suite 24/24; full Flutter suite
    894/894; `flutter analyze`, changed-file formatting, and `git diff --check`
    clean. GitNexus follow-up impact: Dashboard MEDIUM, nav MEDIUM, Ask LOW,
    Activity row MEDIUM; shared `BloomAmount` impact was HIGH and its code was
    left unchanged. Follow-up detect-changes: 8 files, 9 symbols, 0 processes,
    LOW. HomeShell route fixture cleanup
    hangs on Drift streams, so navigation pill geometry, semantics, and tap
    behavior are covered directly. Dashboard coverage asserts visible streak /
    period values at 320 / 402 px and 1.5× / 2×; Ask semantics and two-line
    foreign-currency amounts are covered. Physical-device acceptance remains
    open.
  - Independent review approved the Weekly Review slice; broader T-167c
    acceptance remains open. GitNexus pre-edit `_buildCardView` impact
    was LOW/exact; final graph detection is recorded in WORKLOG.
  - Responsive Slice verification: production route suite 14/14 and all
    Review tests 26/26; no provider/data behavior changes. The route test
    covers 402×874/default portrait, 568×320/1.5×/24dp, and
    568×320/2×/48dp with the real floating pill. Independent review
    approved the updated diff. Physical-device QA remains pending.



- [ ] T-154b [P2] Sort: inline corrections and guess refresh before Keep.
      Code merged: a "Not right?" action under the card offers "Wrong payee
      or amount" (the existing correction sheet), "Not a spend (transfer or
      refund)" and, for SMS rows, "Duplicate or not a transaction", each with
      Undo. After any edit that changes the payee, amount or direction, the
      guess is recomputed through the categorizer read path (ignoring the
      stale merchant link) and Keep is disabled until it settles (and stays
      disabled if it fails). Keep then stores the recomputed guess without a
      feedback row, rule or alias; a category the user chose always wins.
      Evidence (cloud): `sort_inline_correction_test.dart` (4 tests) red before;
      full suite 1212/1212; NY-TZ touched dirs 412/412. Review: six findings
      (user choice overwritten, Undo losing the guess, failure re-enabling
      Keep, title, silent failure) fixed. Open: owner-phone check.
      Details: [T-154](docs/tasks/T-154.md).

- [ ] T-198 [P1] Readable payee names. Code merged: one display-only
      `payeeDisplayName` (label -> merchant name -> SMS payee text -> R4 brand
      via `PayeeKey.displayBrand` -> stored VPA -> note) titles Activity, Sort,
      detail and Top merchants; `payzomato@hdfcbank` and
      `zomato.eternaltsp.payu@hdfcbank` show "Zomato", phone and gateway VPAs
      stay as stored. Root cause of repeated "Unknown": Top merchants'
      `GROUP BY name` bound to `categories.name`, splitting rows per category.
      It now groups per payee identity (never merging different payees),
      titles payee-less rows "Unnamed · <category>", and adds the VPA when two
      payees share a title. No writes: the correction sheet is prefilled with
      the stored `merchant_raw` and no longer turns an untouched empty field
      into `''`. Activity filter/search and CSV ("UPI ID" column) keep the
      VPA. Evidence (cloud): repository/widget tests red before; full suite
      1205/1205; NY-TZ touched dirs 620/620. Review: six findings (neutral
      label merges, pay-prefix, person names, blank groups, filter/search/CSV)
      fixed before commit. Open: owner-phone check.
      Details: [T-198](docs/tasks/T-198.md).

- [ ] T-197 [P1] Activity keeps its scroll position after an edit. Root
      cause: Activity chose portrait vs short-height from the
      keyboard-reduced Scaffold height (and HomeShell drops its navigation
      padding while a keyboard is up); the category picker autofocuses its
      search, so the keyboard flipped the layout and back, rebuilding the
      list at offset 0. The choice is now frozen while a keyboard is visible;
      pages and keyset queries are unchanged. Also fixed a pre-existing 7-13dp
      Activity header overflow on 360dp-wide phones. Evidence (cloud):
      `activity_scroll_retention_test.dart` (402x874, 964x434 and a HomeShell
      360x640: two loaded pages, older anchor row, edit under a keyboard
      inset, swipe confirm and undo) red before (offset 14504 -> 0, shell
      14835 -> 0), green after in UTC, Asia/Kolkata and America/New_York;
      full suite 1208/1208. Review: the first fix missed the HomeShell
      padding case (found by review, fixed). Open: owner-phone check.
      Details: [T-197](docs/tasks/T-197.md).

- [ ] T-196 [P1] Transaction details card on the detail screen. Code
      merged: "TRANSACTION DETAILS" lists only stored fields (UPI ID/VPA,
      payee in SMS, reference/RRN, channel, account hint, payment source,
      direction, date, balance, currency, non-settled status, parser), each
      with a 48dp copy button and "Label: value" semantics; the technical
      disclosure no longer repeats them. Evidence (cloud): card/screen tests
      red before the card existed; 2.0x landscape 964x434 without overflow;
      full suite 1192/1192; NY-TZ transactions + repositories 225/225.
      Review: payment-source name now live (finding fixed). Open:
      owner-phone check.
      Details: [T-196](docs/tasks/T-196.md).

### Scale, privacy, and maintainability

- [ ] T-115 (@codex) [P1] Profile startup, import, and model memory.
      Module: bootstrap, capture, LiteRT-LM.
      Depends: signed profile/release build and target device.
      Next: record cold start, 10k-message import, baseline/navigation/model PSS,
      native/GPU caches, and idle/background release evidence.
- [ ] T-118 (@codex) [P2] Explain recurring ineligibility.
      Module: recurring detector/repository/UI.
      Depends: structured eligibility reason model.
      Next: show per-merchant progress, cadence/amount gaps, and fragmented
      identity warnings rather than a bare empty state.
- [ ] T-130 (@codex) [P2] Reduce residual architectural coupling.
      Module: data/domain architecture. Brief: [T-130](docs/tasks/T-130.md).
      Depends: T-165d interface inventory. T-165b/c/d own the transfer query,
      integer-paise migration and repository split.
      Next: map the database↔duplicate-rule import cycle and decompose only
      confirmed residual seams.

### Accessibility, security, and release
- [ ] T-128 (@codex) [P1] Complete accessibility and failure-state coverage.
      Module: shell and all primary Bloom screens.
      Depends: stable P0 flows.
      Gap: unlabeled gesture controls, missing selected semantics, sub-48dp
      targets, light-theme contrast failure, weak large-text/semantics tests,
      and several errors rendered as empty states.
      Next: use semantic Material controls, ≥48dp targets, corrected tokens,
      1.5×/2× and multi-viewport widget tests, then TalkBack acceptance.
- [ ] T-090 (@codex) [P4] App lock.
      Module: app lifecycle/security.
      Depends: T-122/T-124 recovery contracts.
      Next: design launch/resume lock with unavailable-biometric and recovery
      paths that do not weaken SQLCipher.
- [ ] T-091 (@codex) [P4] Privacy-safe home widget.
      Module: Android widget.
      Depends: T-090.
      Next: define locked/unlocked disclosure and a configurable aggregate-only
      surface.
- [ ] T-094 (@codex) [P5] Distribution and portfolio release package.
      Module: release/product.
      Depends: T-090, T-115, T-125, T-128.
      Next: signed release, SMS-permission declaration or maintained sideload
      path, screenshots, privacy/architecture story, rollback checklist.

### Planned product outcomes

- [ ] T-102 (@codex) [P2] Local statement import and reconciliation.
      Module: new statement import/reconciliation module. Brief: [T-102](docs/tasks/T-102.md).
      Depends: T-102a source/fingerprint contract first; T-100a relationship
      semantics; accepted ADR only if durable schema is needed. Coordinates T-190h.
      Next: specify CSV preview, account mapping, idempotency, guarded matching,
      ambiguity review, and transactional rollback.
- [ ] T-100 (@codex) [P2] Reimbursement, refund, and reversal tracking.
      Module: transaction relationships and analytics. Brief: [T-100](docs/tasks/T-100.md).
      Depends: T-100a audit and accepted accounting contract; PV-04
      explanations; T-165c only if amount representation is touched.
      T-126/PV-02 is presentation evidence, not a net-spending contract.
      Next: define canonical net totals and reversible source-preserving links.
- [ ] T-101 (@codex) [P3] Recurring calendar and future-message detection.
      Module: existing expected-event store/matcher and review UI. Brief: [T-101](docs/tasks/T-101.md).
      Depends: T-101a gap audit; reuse the existing T-138 expected-event pipeline.
      Next: snooze, cancel, missed and price-change states with guarded
      settlement matching; expected events never enter settled totals.
- [ ] T-098 (@codex) [P3] Monthly category budgets.
      Module: dedicated budget schema/repository/UI. Brief: [T-098](docs/tasks/T-098.md).
      Depends: T-100 canonical net contract and an accepted budget ADR.
      Gap: the current overall monthly budget/merchant-cap prototype is not this
      feature and uses `baselines`.
      Next: per-category/per-month limits, currency, eligibility and safe
      migration away from prototype storage.
- [ ] T-096 (@codex) [P3] Tolerant free-text category resolution.
      Module: assistant/category identity.
      Depends: stable category aliases.
      Next: add typo-tolerant matching that refuses ambiguity.

### Planned rework — task briefs in `docs/tasks/`

Full detail lives in one brief per parent ticket. Read `TASKS.md` to pick a task,
then `docs/tasks/T-NNN.md` for **only the sub-task you claimed** — typically
60–110 lines. Do not read the design documents unless a brief points you at a
section. See `docs/tasks/README.md` for the format.

Sub-task ids suffix the parent (`T-146a`). Parent ids are containers and are
never worked directly. Sizes: `~S` under half a day, `~M` up to a day, `~L` split
further before claiming.

#### SMS intelligence — `docs/sms-intelligence-design.md`

Phase A blocks B; B blocks C and D.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-133a** | P1 | ~L | Shape scoring and quarantine store | T-129 |
| **T-133b** | P1 | ~M | "Messages we couldn't read" + retry on upgrade | T-133a |

Completed briefs are mapped in `docs/archive/planning-cleanup-2026-09.md`.
T-143c1–c3 were verified complete on 2026-10-03 (`ff7b1e3`, `cec0b3a`;
shadow pipeline, diff and dev metrics tests pass). T-140's production integration gaps are handled by T-177a/b.

#### UI gaps — `docs/ui-gaps-and-redesign.md`

T-152a unblocks four screens. T-150a precedes the Ask rebuild. T-153a precedes
T-154a.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-151b** | P2 | ~S | Bubble geometry and verdict answers | T-151a |
| **T-151d** | P2 | ~M | Thinking, model-missing, no-answer states | T-151b |
| **T-151e** | P3 | ~M | Inline charts and follow-up chips | T-151b |
| **T-149a** | P3 | ~M | Profile shell and personalisation | — |
| **T-149b** | P3 | ~M | Habits and money shape | T-149a |
| **T-149c** | P3 | ~S | Data footprint and privacy posture | T-149a |

Completed T-145a/b, T-146a/b, T-147a/b, T-148a/b, and T-152a are mapped in
`docs/archive/planning-cleanup-2026-09.md`.

Follow `PLAN.md` for delivery priority: finish T-176 physical-device
acceptance, then T-177a. T-157b and PV-02 passed independent review and were
removed from the active board. T-153a–c were verified complete on 2026-10-03
(`635e63d`, `a211935`, `ebf62cd`; 26 review tests pass); T-154b is now In
Review. T-151b remains open pending a supported
affordability intent and deterministic verdict contract.

#### Flutter refactor, no behavior change — `docs/tasks/`

Scoped to presentation helpers, the oversized `transaction_detail_screen.dart`,
Riverpod boundaries, and shallow render-only tests. T-159a is complete; see the
historical mapping in `docs/archive/planning-cleanup-2026-09.md`.

| Task | P | Size | Summary | Depends |
|---|---|---|---|---|
| **T-156c** | P2 | ~M | Standardize TransactionDetailScreen's presentation | T-158c |
| **T-158b** | P2 | ~M | Extract `TransactionDetailController` | T-157b |
| **T-158c** | P2 | ~M | Extract sub-widgets into `detail/` | T-158a (complete) |
| **T-159c** | P3 | ~M | Convert remaining shallow render tests to behavioral | T-158c |

Completed T-156b, T-157a/b/c, T-158a/d, and T-159a/b are mapped in
`docs/archive/planning-cleanup-2026-09.md`.

## Backlog

- [ ] T-190 [P2] Plan credit-card purchase, bill, payment, refund, and failure
      accounting. **Do this last among the newly requested tasks.**
  - Acceptance: Produce a grounded scenario map for card purchases, statement
    generation, bill payments, full/partial refunds, failed/reversed payments,
    and statement reconciliation. Define which source rows remain immutable,
    lifecycle/duplicate links, settled-spend and available-credit boundaries,
    user review, backup, and undo requirements; identify gaps in T-100/PV-04.
    Planning only; no schema or implementation until separately approved.
  - Dependencies: reuse T-100 refund/reimbursement links and PV-04 lifecycle
    explanation; inspect actual card and payment-source data first.
  - Privacy: synthetic scenarios only; no live statements or SMS.
  - Rollback: planning artifact only; no runtime behavior changes.
  - Plan drafted and independently reviewed (proposed, owner decisions open):
    [credit-card accounting](docs/plans/credit-card-accounting.md),
    [ADR 0020 (Proposed)](docs/decisions/0020-credit-card-accounting.md),
    phased briefs [T-190a1–h2](docs/tasks/T-190.md). No child is Ready.

<!-- Groom future work here before promoting it to Ready. -->

Sequenced roadmap (proposed): [docs/plans/roadmap.md](docs/plans/roadmap.md);
release/holdout gates: [release-gates.md](docs/plans/release-gates.md).

Before promoting an item to `Ready`, keep its brief actionable and include
acceptance evidence, dependencies, privacy impact, and rollback path. Keep one
implementation task in progress at a time.

#### Capture correctness and observability

- [ ] T-160d [P1] Extract reusable paged-list controller/state from Activity without changing review-queue behavior; characterize loading, error, retry, and exhaustion states first.
- [ ] T-161e [P1] Add end-to-end tests for scan outcomes: newly created, already known, parsed-but-duplicate, unparsed, individual failure, and native rejection.
- [ ] T-162b [P1] Define sender-onboarding evidence format (header, template fingerprint, fixture, expected result) and add a review gate before expanding `SmsFilter` allowlist.
- [ ] T-162c [P1] Add unsupported-sender telemetry aggregated only by safe reason/category; prove personal-number bodies and identifiers are never persisted or logged.
- [ ] T-162d [P2] Add deterministic employer/payroll alias recognition layered after parser evidence verification; require credit direction and account/channel context.
- [ ] T-163a [P1] Make the SMS scan entry a reusable capture-status component for Activity, Settings, onboarding completion, and empty states.
- [ ] T-163b [P2] Add scan cancellation/resume semantics with checkpoint preservation and explicit user-visible partial-result state.

#### Product-value research and review

Historical review: `docs/archive/reviews/product-value-review-2026-08.md` and
`docs/product-quality-review.md`; T-172e's evidence boundary and waiver are in
`docs/tasks/T-172.md`. Target-device screen-smoke is an observation, not a
human-validation pass.

#### Product-value implementation briefs

The review produced dependency-ordered follow-ons; groom one at a time before
promoting it to `Ready`. Full contracts, owners, rollback paths, and acceptance
metrics are in `docs/tasks/T-172.md`.

- [ ] PV-01 [P0] Complete full-history keyset search/filter and timestamp contract. Depends: T-160b–d, T-164a–b, T-164e.
- [ ] PV-03 [P0] Add privacy-safe capture outcome ledger, reason buckets, and bounded retry. Depends: T-161a–e, T-162a–c.
- [ ] PV-04 [P0] Unify lifecycle, duplicate, transfer, refund, and excluded-source explanations. Depends: T-164c–d, T-135.
- [ ] PV-05 [P0] Share correction/undo and complete backup/reset/raw-SMS/native-artifact recovery proof. Depends: T-159a, T-157b, T-170a–b.
- [ ] PV-06 [P1] Add salary income semantics and reversible source correction. Depends: T-162a, T-166a–b.
- [ ] PV-07 [P1] Apply the accessible primary-flow contract and device matrix. Depends: T-167a–h.
- [ ] PV-08 [P1] Add the data-footprint disclosure and release review package. Depends: T-169b, T-171a–b.

#### Smart transaction assistance — `docs/plans/smart-transaction-assistance.md`

- R1 done 2026-10-02 (rule replacement, exact matching with legacy tier,
  history rule status). Next: R2 one payee identity across live/history/
  catch-up — done 2026-10-02; R3 rules and Ask on resolved identity —
  done 2026-10-02. Deferred: v20 re-key of stored payee keys + reversible backfill of
  unresolved imported rows. Audit notes: merchant memory and LLM steps are not wired in
  `categorizerProvider`.

- [ ] T-177b [P1] Integrate confirmed payee memory with a P2P eligibility guard.
- [ ] T-177c [P1] Complete correction scopes, rule conflicts, and undo.
- [ ] T-177d [P1] Add paged grouped review and persistent deferral.
- [ ] T-177e [P2] Reuse categories and support evidence-only optional descriptions.
- [ ] T-177f [P1] Shadow-evaluate and stage opt-in assistance release.
- [ ] T-177g [P3] Assess local receipt/screenshot matching.

#### Grounded AI

Plan with slices b1–d3, metrics and pass thresholds (proposed, not Ready):
[grounded-ai-validation](docs/plans/grounded-ai-validation.md).

- [ ] T-178b [P1] Validate forecast ranges, data coverage, and backtesting.
      Anomaly and forecast insights are hidden until they emit T-178a typed
      claims (see docs/architecture.md insight claim contract).
- [ ] T-178c [P2] Add typed Hinglish assistant intents over validated results.
      Narrative insights were removed in T-178a; any model-written insight
      text must be redesigned as selection of existing claim ids.
- [ ] T-178d [P2] Add local evaluation, performance gates, and staged release.

#### Transaction integrity, data model, and performance

- [ ] T-164b [P1] Move Activity filtering/search to SQL with indexed fields and paged results; preserve every current filter semantic.
- [ ] T-164c [P1] Add explainable visibility flags for deleted, duplicate-suppressed, pending, reversed, transfer, and excluded-payment-source transactions.
- [ ] T-164d [P2] Add “show excluded” Activity filter and detail explanation without letting excluded rows alter spending/budget totals.
- [ ] T-165a [P1] Profile 10k/50k transaction Activity rendering and query latency on release hardware; record thresholds and baseline evidence.
- [ ] T-165c [P2] Plan and ADR an integer-paise migration, including lossless conversion, compatibility, rollback, and migration tests.
- [ ] T-165d [P2] Split `TransactionRepository` reads/commands/corrections behind domain DTOs; prove existing provider and migration behavior.
- [ ] T-166a [P1] Implement explicit salary income analytics card and period totals that include credits but never treat transfers/refunds as salary.
- [ ] T-166b [P2] Add income source review/correction flow with undo and optional historical relabel preview.

#### UI quality, accessibility, and refactoring

- [ ] T-167b [P0] Add semantic labels, selected state, and 48dp minimum targets to custom Activity, Dashboard, Settings, and Review controls.
- [ ] T-167d [P1] Replace bespoke gesture-only controls with semantic Material controls or equivalent explicit semantics.
- [ ] T-167e [P0] Audit every root-tab screen, nested sheet, and detail route for FAB/action-button overlap with the bottom navigator, gesture area, keyboard, or system navigation inset; record viewport screenshots and exact affected widgets.
- [ ] T-167f [P0] Introduce one shared safe-area/FAB placement contract that reserves bottom-navigation height, system gesture insets, keyboard insets, and minimum touch clearance; migrate Dashboard, Activity, Review, Insights, Settings, and all nested action sheets without per-screen magic offsets.
- [ ] T-167g [P1] Add behavioral widget tests at small Android, gesture-navigation, keyboard-open, large-text, and landscape viewports proving every primary FAB/button is visible, tappable, and not hit-tested beneath bottom navigation.
- [ ] T-167h [P1] Add golden/regression coverage for root navigation plus floating actions in light/dark themes; fail on visual intersection or <48dp exposed tap target.
- [ ] T-167i [P2] Standardize bottom-sheet action bars and scroll padding on the same inset contract, including long forms, validation errors, and hardware-keyboard layouts.
- [ ] T-168a [P1] Extract `TransactionDetailScreen` pure presentation helpers and subwidgets behind characterization tests (T-159a prerequisite).
- [ ] T-168c [P2] Route remaining bespoke sheets/dialogs through Bloom helpers and add API-level presentation tests.
- [ ] T-168d [P2] Establish a visual-regression golden suite for Activity, SMS scan, salary income, errors, and dark/light themes.
- [ ] T-169a [P1] Add a dedicated transaction-import progress model shared by onboarding, Settings, and Activity; remove duplicated display counters.
- [ ] T-169b [P2] Add a privacy/data-footprint screen explaining local SMS retention (ADR 0021: linked source SMS kept, unlinked SMS removed after 7 days), parse status, backup inclusion, and safe deletion.

#### Reliability, privacy, and release readiness

- [ ] T-170a [P0] Add fault-injection tests for database-write, parser, channel, lifecycle, and native inbox query failures; prove retries are bounded and idempotent.
- [ ] T-170b [P1] Verify ADR 0021 retention on a device: linked SMS survive the nightly purge, unlinked SMS go after 7 days, backups include linked SMS, deletion and recovery behave. Host tests landed with T-195 (review PASS 2026-10-03); device-backed evidence is still required, including the owner-phone check from T-195: run Settings → "Restore SMS sources" and confirm a transaction older than 30 days shows its SMS.
- [ ] T-170c [P1] Add release-build smoke tests for permission recovery, first import, resume catch-up, 10k history paging, and salary credit visibility.
- [ ] T-170d [P2] Create a manual QA matrix for supported senders/templates, unsupported-sender telemetry, and false-positive privacy checks.
- [ ] T-171a [P1] Add CI shards for Flutter unit/widget, Android unit, migration, and fixture-contract tests with deterministic failure artifacts.
- [ ] T-171b [P2] Publish performance and accessibility acceptance budgets in docs, then gate release candidates on measured evidence.

## Board rules

- Keep exactly one instance of every `##` workflow heading; handoff automation
  parses them literally.
- Keep only unfinished work. Remove an item after implementation and required
  verification are complete.
- Move at most one implementation task to `In Progress`.
- `In Review` is temporary and contains only unresolved verification/review.
- Record current state in `docs/product-status.md`, durable decisions in ADRs,
  and completed evidence in Git history or `docs/archive/`.
