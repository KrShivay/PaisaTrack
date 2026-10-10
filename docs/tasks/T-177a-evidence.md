# T-177a — Production integration audit: evidence log

Brief: [T-177](T-177.md). Status: owner holdout and device gates open.

## Board evidence (moved from TASKS.md, 2026-10-10)

Verbatim board text at `52f8385`; the board now keeps only a summary line.

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
