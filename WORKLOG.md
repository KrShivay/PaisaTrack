# Current Handoff

## 2026-10-03 — Cloud session: T-195 source SMS provenance

- T-195 (ADR 0021): SMS behind a transaction or "Not a transaction" are kept;
  unlinked SMS expire after 7 days (flag `raw_sms_retention_days` retired);
  backups carry linked SMS; Settings → "Restore SMS sources" re-links exact
  inbox matches (`txn_<id>` + evidence spans), skips and counts the rest.
  Shared `readInboxPages` now drives history import, catch-up and re-link.
  Backup +~340 B per kept SMS (16 MiB cap ≈ 12k SMS-backed transactions).
- Evidence: suite 1185/1185, NY-TZ touched dirs 642/642, analyze 0.
  Owner phone still needs the re-link check. The T-177 R3 entry is in Git
  history (`c381756`).

## 2026-10-03 — Owner-phone defects fixed; release 0.1.6+2015

- Owner-phone QA (data exported by owner): UNDO-1 passed (category change,
  toast over detail, Undo restored it). Found and fixed: ISO/INR claim copy
  and a false "committed to rent" caption (`5dd0248`); Ask could not find
  VPA-only payees such as `payzomato@hdfcbank` — R4 brand-word matching with
  disclosed payees, plus a reviewer-found "ola"/multi-word regression fix
  (`8e4eb65`); emulator-matrix fixes (48dp Ask rows, compact landscape ring,
  provenance badge; `82ba900`); landscape nav/Ask orb under the right system
  bar and Activity header eating the viewport at 2.0x (`9dac2c5`, DRY
  refactor before merge; test fix `89a20c3` after main went red); Trends
  claim titles and day-7 minimum for category deltas (`a09bd1c`); readable
  Ask answers with a "How this was counted" disclosure (`dfb05e6`).
- Release 0.1.6+2015 (`13dd4d5`): suite 1174/1174, Gradle 31/31 + 10/10,
  installed in place (firstInstallTime unchanged, hash matched), cold launch
  1040 ms, published `apk-downloads` `5747e3c`. Open: landscape/2.0x/3-button
  recheck on this build (phone back in portrait); the stale pre-day-7
  category card cleared once insights regenerated. VPA-only rows still display raw
  VPAs, Top merchants shows several "Unknown" rows. R2 entry is in Git
  history (`f730857`). T-195–T-198 are now Ready on the task board.
  Follow-up release 0.1.7+2016 (`016465d`, adds the month-over-month badge
  fix `37beb17`): suite 1176/1176, installed in place, published
  `apk-downloads` `0e151f2`.

## 2026-10-03 — Roadmap planning and docs cleanup (no code)

- Added proposed plans: [roadmap](docs/plans/roadmap.md) (graph, sub-slice
  ledger, next slice), [release gates](docs/plans/release-gates.md) (T-194,
  T-177a holdout), [risk register](docs/plans/risk-register.md),
  [backup import](docs/plans/backup-import.md) (deferred),
  [credit-card accounting](docs/plans/credit-card-accounting.md) + ADR 0020
  (Proposed) + briefs T-190a1–h2, and
  [grounded-AI validation](docs/plans/grounded-ai-validation.md) (T-178b–d).
  Groomed briefs T-100/101/102/098/130; the board had nothing Ready at that
  handoff. The later owner requests T-195–T-198 are Ready.
- Docs: [index](docs/README.md), [ADR index](docs/decisions/README.md) (0013
  unused, next 0021), `scripts/check_doc_links.py` (clean), archived the
  2026-08 value review, restored the missing `## Ready` heading.
- Reviews: T-190 and roadmap each passed independent Luna review after
  revision (T-190 R2 approve-with-changes, applied; roadmap R3 accept).
- Next code slice: T-165b (+ stale `transfer_leg` cleanup) as a parallel data
  lane; T-177a holdout stays the product-priority gate. Owner decisions are
  listed in the roadmap and T-190 plan. No app tests run (docs only).
  The T-177 R1 entry is in Git history (`239c2d2`).
