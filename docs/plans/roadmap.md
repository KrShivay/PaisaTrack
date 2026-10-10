# Sequenced roadmap

Status: proposed sequencing (updated 2026-10-10). Product priorities and
invariants: [PLAN.md](../../PLAN.md). Current behavior:
[product status](../product-status.md), [architecture](../architecture.md).
Executable queue: [TASKS.md](../../TASKS.md). This file owns waves, parallel
groups, hot-file locks and the dependency ledger; it does not change release
gates or claim completion.

## Waves (owner batch 2026-10-10)

The owner wants the app smooth, fast and intelligent, and shipping faster.
Waves run in order; inside a wave, children run in parallel when their brief's
parallel group and the hot-file locks below allow.

| Wave | Goal | Children (briefs) | Gate to start |
|---|---|---|---|
| 1 | No flicker, honest categories, fast tests | T-203a/b/d/e; T-205a/b; T-210a/c1/d; T-204a/c/d/e/i/m/o; T-208a/e/h/l; T-207a–e; T-211a; T-162b1; T-171b1/b2a | none |
| 2 | Apply foundations | T-203c/f/g2–g5b/g6; T-205c/d; T-210b/g1/c2–c5/e/f; T-204b/f/g/h/j/k/l; T-208b/d/j1/c; T-207f/ag/g/h/i; T-211c; T-162b2 | wave-1 parents' Depends |
| 3 | Screens and owner-decided features | T-204 screens (n–al) per folder; T-205e–h + T-211b/e (ADR 0036); T-207j–q (ADR 0034); T-165c1–c6 (ADR 0033); T-203h/i; T-208f/g/i | owner accepts ADRs |
| 4 | Intelligence surfaces and money | T-207r–am (ADR 0035 for w+); T-204s–aa, am, ao; T-165c7–c15; T-100 (T-209); T-162d | wave 3 |
| 5 | Accounting and release | T-190 slices; T-098; T-178b–d; T-102; T-171b3/b4; T-170d; T-177g; T-130 | card decisions; T-100c |

Device/owner gates in `In Review` (T-176, T-167c/j, T-199, T-200, T-202,
T-194, T-177a, T-154b, T-196–198) stay open in parallel; batch them into one
owner phone session.

### Hot-file locks

Only one in-flight child may edit each file below; later children rebase on
the merged result. Briefs' Depends lines already serialise the known pairs.

| File | Order of owners |
|---|---|
| `lib/data/db/database.dart` (+ generated) | one schema child at a time: T-207j → T-165c3 → T-207w (provisional order); T-208c/i index/startup edits never concurrently with a schema child |
| `lib/features/dashboard/dashboard_providers.dart`, `dashboard_widgets.dart` | T-203c → T-204r (move-only split) → T-204q/s–v → T-207z/aa/ab |
| `lib/features/transactions/transactions_providers.dart` | T-203f → T-203g6 → T-204w |
| `lib/capture/sms_backfill.dart`, `sms_ingestion.dart` | T-203e → T-208f → T-207m |
| `lib/intelligence/nightly_job.dart` | T-207n → T-207ah |
| `lib/enrichment/categorizer.dart` | T-205c → T-162d2 |
| `lib/features/settings/settings_screen.dart` | T-203g2b → T-204p → T-204ad |
| `lib/core/theme/category_visuals.dart` | T-204j → T-211c |
| `lib/capture/parser_cascade.dart` | T-207ak only |
| `.github/workflows/*`, `dart_test.yaml` | T-210a → T-210b → T-210f → T-171a |

### Schema queue

Provisional versions are assigned at start ([rule](../schema.md#planned-additive-areas)):
`sms_facts` (ADR 0034) → minor-unit money columns (ADR 0033) → dashboard
tables (ADR 0035). T-205 and T-211 need no schema change (ADR 0036).

## Principles

- One child per worker; parallel workers only on disjoint files. New work
  stays Backlog until its brief is groomed.
- Keep device/private-data gates open until their stated evidence exists.
  Synthetic fixtures prove logic only. See [release gates](release-gates.md)
  and [backup import acceptance](backup-import.md).
- Audit and reuse current links, expected events, eligibility and archive
  support before schema work. Schema changes need an accepted ADR, additive
  migration, backup/delete coverage and migration tests.
- Source currency and source rows are preserved; one canonical eligibility
  and net-spending contract feeds aggregates, budgets and insights.

## Dependency graph

Arrows point from prerequisite to dependent work. Physical/device evidence
remains a gate even where synthetic work can proceed in parallel. This graph
is a **parent-level overview**: T-101, T-102, T-098 and T-178 appear as parent
nodes, and card/refund slices only where cross-task edges matter. The
[sub-slice ledger](#complete-implementation-sub-slice-sequence) and each brief's Depends line are authoritative.

```mermaid
flowchart TD
  T176[T-176 physical route acceptance] --> T177a[T-177a holdout + capture gates]
  T101[T-101 expected-payment product gaps]
  T177a --> T177b[T-177b identity memory]
  T177b --> T177c[T-177c correction and undo]
  T177c --> T177d[T-177d grouped review]
  T177c --> T177e[T-177e category reuse]
  T177d --> T177f[T-177f staged release]
  T177e --> T177f
  T177f --> T177g[T-177g receipt feasibility]
  T102[T-102 statement reconciliation] -. coordinates .-> T177g

  T177a --> T178b[T-178b forecast validation]
  T178b --> T178c[T-178c typed Hinglish intents]
  T178c --> T178d[T-178d eval, performance, staged release]
  T115[T-115 device profiling] --> T178d
  T177f --> T178d

  PV02[T-126 / PV-02 truthful-number presentation: complete]
  T178a[T-178a evidence and eligibility contract: complete]
  T100a[T-100a audit and accounting contract] --> T100b1[T-100b1 guarded relationship persistence]
  T100b1 --> T100b2[T-100b2 preview, review and undo]
  PV04 --> T100b2
  T100b2 --> T100c[T-100c canonical net totals]
  PV04 --> T100c
  T165c[T-165c integer-paise migration] -. only if amount representation changes .-> T100c
  T100c --> NET[Canonical net-spending contract]
  NET --> T098[T-098 category budgets]
  T190a1[T-190a1 read-only card source audit] --> T190a2[T-190a2 ownership decision + preview/undo]
  T165b[T-165b indexed transfer matching + stale-edge cleanup, complete] --> T190b1[T-190b1 stale-edge cleanup, closed via T-165b]
  T190b1 -. only before reconciliation is invoked .-> T190a2
  T190a1 --> T190a2
  T190a2 --> T190b2[T-190b2 payment allocation]
  T100b2 --> T190b2
  T157b[T-157b shared correction/undo: complete] --> T100b2
  T190b1 --> T190b2
  PV04 --> T190b2
  PV04 --> T100b2[T-100b2 preview/review/undo contract]
  T164c --> T190c[T-190c holds, declines, reversals]
  T190a1 --> T190c[T-190c holds, declines, reversals]
  T164c[T-164c explainable visibility flags] --> PV04[PV-04 shared explanation contract]
  T164d[T-164d show-excluded Activity] --> PV04
  T135[T-135 shared lifecycle/net eligibility contract] --> PV04
  PV04 --> T190g1[T-190g1 single review + undo]
  T190a1 --> T190d[T-190d refunds and cashback via T-100]
  T100c --> T190d
  T190c --> T190d
  PV04 --> T190d
  T190c --> T190e1[T-190e1 card charge classification]
  T190a1 --> T190e1
  T190d --> T190e1
  T190a1 --> T190e2[T-190e2 EMI + cash advance]
  T190c --> T190e2
  T190e1 --> T190e2
  T190b2 --> T190f2[T-190f2 liability/available-credit projection]
  T190c --> T190f2
  T190e1 --> T190f2
  T190d --> T190f2
  T190e2 --> T190f2
  T190f1[T-190f1 snapshot persistence + restore] --> T190f2
  T190f2 --> T190g1
  T190a2 --> T190g1
  T190g1 --> T190g2[T-190g2 bulk review; integrate card explanations into PV-04]
  T190g2 --> T190h1[T-190h1 shared statement importer integration]
  T102[T-102 statement reconciliation] --> T190h1
  T190f1 --> T190h1
  PV04 --> T190h1
  T190h1 --> T190h2[T-190h2 card account mapping + review]
  T190a2 --> T190h2
  PV04 --> T190h2
  T100c -. when refunds appear .-> T190h2

  T164c --> PV04
  T164d --> PV04
  T135 --> PV04
  T157[Shared correction / undo, T-157b complete] --> PV05[PV-05 recovery proof]
  T159[T-159a correction/detail regression] --> PV05
  T170a[T-170a fault-injection reliability] --> PV05
  T170b[T-170b raw-SMS/device recovery proof] --> PV05
  BACKUP[Backup import acceptance] --> T170b
  T179[T-179a isolated recovery identity gate] --> BACKUP
  T161[T-161 capture outcome counts] --> PV03[PV-03 outcome ledger]
  T162[T-162 salary capture coverage] --> PV03
  T162 --> PV06[PV-06 salary semantics]
  T166[T-166a/b salary analytics and correction] --> PV06
  T167[T-167a-h accessible primary-flow work] --> PV07[PV-07 accessible primary flows]
  T115 --> PV08[PV-08 footprint and release review]
  T169[T-169b data-footprint disclosure] --> PV08
  T171[T-171a/b CI and acceptance budgets] --> PV08
  T170b --> PV08
  T160[T-160b-d Activity paging] --> PV01[PV-01 full-history search]
  T164[T-164a/b/e Activity filters] --> PV01
  T165d[T-165d repository/domain boundary] --> T130a[T-130a residual import-cycle cleanup]
  T130a --> T130b[T-130b remaining module decomposition]
  T164c --> T164d

  T090[T-090 app lock] --> T091[T-091 privacy-safe widget]
  T090 --> T094[T-094 distribution package]
  T115 --> T094
  T125[T-125 recovery contract] --> T094
  T128[T-128 accessibility and failure-state coverage] --> T094
  T170b --> T094
```

T-190 slices and their dependencies are defined in [T-190](../tasks/T-190.md)
and the [credit-card plan](credit-card-accounting.md). T-102 is a prerequisite
for T-190h1/h2. PV-04 is the shared explanation contract
that precedes T-190b2 and T-190g1; T-190g2 adds card explanations to that
contract. The T-100/PV-02 scope distinction is documented in
[T-100](../tasks/T-100.md#dependencies-and-readiness).

## Critical path and parallel lanes

1. Finish open T-176 physical route evidence, then close T-177a only after the
   real chronological holdout and live/resume device coverage pass. Existing
   synthetic replay and capture provenance report are not substitutes.
2. T-177b–f form the assistance path. T-178b–d depend on validated evidence
   and release evaluation; device profiling (T-115) is also required before
   staged release.
3. T-100 accounting semantics and audited links precede category budgets
   (T-098) and card refunds (T-190d). T-102 can run in parallel after its own
   source/fingerprint and import contract are approved; T-190h coordinates its
   statement lifecycle with T-102.
4. T-101 can audit and close gaps in the existing expected-event pipeline
   independently; it must not turn expected obligations into settled spend.
5. T-165b/c/d own the transfer query, paise migration, and repository split
   respectively. T-130 owns only remaining dependency/coupling cleanup after
   those overlaps are removed.
6. Backup acceptance, T-170b, PV-05, T-090/091/094, and T-194 retain their
   separate physical/release evidence. Passing one does not close another.

Parallelizable lanes after T-176's current release blocker is handled:

- Assistance: T-177a evidence gate, then T-177b–f; T-177g remains feasibility.
- Grounded AI: T-178b–d after T-177a; profiling may proceed in parallel.
- Ledger integrity: T-100 accounting contract, T-101 event gaps, and T-102
  statement import can be separately groomed; T-098 waits on T-100.
- Card accounting: T-190a…h follows its plan and shares T-100/PV-04/T-102.
- Reliability and architecture: T-194, T-170b/backup acceptance, T-165b/c/d,
  T-130, and PV-01…08 follow their listed dependencies.

## Completed prerequisite nodes

| Node | Status | Evidence/reference |
|---|---|---|
| T-178a evidence and eligibility contract | Complete | [Grounded AI plan](grounded-ai-validation.md) prerequisites; definition: [T-178 brief](../tasks/T-178.md). |
| T-126 / PV-02 truthful-number presentation | Complete | Product status; see [T-100 scope note](../tasks/T-100.md#dependencies-and-readiness). |

## Complete implementation sub-slice sequence

Dependencies below are prerequisite-to-dependent; “conditional” means the
brief requires that dependency only if its stated audit condition is met. Sizes
are planning estimates. Owner-run device gates remain open independently.

| Slice | Work | Size | Depends |
|---|---|:---:|---|
| T-100a | Audit and accounting contract | M | None |
| T-100b1 | Persist guarded refund relationships | M | T-100a; accepted ADR |
| T-100b2 | Preview, review, durable undo | M | T-100b1; T-157b; PV-04 |
| T-100c | Canonical net totals | M | T-100b2; T-165c if amount representation changes; T-164c/d; PV-04 |
| T-101a | Expected-event gap and lifecycle audit | S | None |
| T-101b | Calendar/review and explicit event actions | M | T-101a; T-167/PV-07 as applicable |
| T-101c | Missed/price-change follow-up | S | T-101b; audit product decision |
| T-102a | Source and fingerprint contract | M | None; coordinate T-100 and T-190h |
| T-102b | Parse and preview | M | T-102a; T-100a; T-165c if amount storage is affected |
| T-102c1 | Atomic apply and import idempotency | M | T-102b; ADR; T-100 relationship semantics; PV-04 |
| T-102c2 | Review decisions and import undo | M | T-102c1; T-102b |
| T-098a | Budget contract and prototype migration plan | S | T-100a/c; accepted budget decisions |
| T-098b | Dedicated category/month model | M | T-098a; T-100 net contract; accepted ADR |
| T-098c | Remaining, thresholds and projection UI | M | T-098b; T-100c; PV-04; T-167/PV-07 |
| T-130a | Import-cycle map and smallest decoupling | S | T-165d interface inventory |
| T-130b | Remaining screen/module decomposition | M | T-130a; T-165d; avoid T-168 overlap |
| T-165b | Indexed owned-transfer query and stale `transfer_leg` cleanup | M | Complete; verification evidence in [T-165b](../tasks/T-165b.md) |
| T-165c | Integer-paise migration design and ADR | M | Conversion inventory |
| T-165d | TransactionRepository boundary | M | Impact review; interface inventory |
| T-177a | Production audit, chronological holdout and live/resume capture gate | M | T-176 device access; consented local holdout |
| T-177b | Safe identity and confirmed-history memory | M | T-177a |
| T-177c | Scoped learning and undo | M | T-177b; T-157b |
| T-177d | Group unresolved payments and remember deferral | M | T-177c; T-153 paging validation; T-176 insets/T-154b correction |
| T-177e | Category reuse and evidence-only descriptions | M | T-177c |
| T-177f | Evaluate and stage release | M | T-177d/e; T-143 shadow isolation; T-115 profiling |
| T-177g | Optional receipt evidence feasibility | M | T-177f; coordinate T-102 |
| T-190a1 | Read-only source audit report | S | T-177a findings; current payment-source code |
| T-190a2 | Ownership/instrument decision with preview and undo | M | T-190a1; ownership/undo review; T-165b stale-edge prerequisite complete |
| T-190b1 | Owned-transfer stale-edge cleanup (delivered by T-165b) | S | Closed by T-165b |
| T-190b2 | Payment event allocation and liability projection | M | T-190a1; T-190a2 confirmed ownership; T-165b (T-190b1 complete); T-100b2 link/undo contract; PV-04 |
| T-190c | Authorization, decline and reversal lifecycle | M | T-190a1; T-164c; PV-04 |
| T-190d | Refunds and cashback using T-100 links | M | T-100 completed contract/tests; T-190a1/c; PV-04 |
| T-190e1 | Explicit card charge classification | M | T-190a1/c; T-100 reversal/refund distinction; owner category/period decision; PV-04 |
| T-190e2 | EMI conversion and cash-advance accounting | M | T-190a/c; T-190e1; owner cash-advance decision; ADR 0020 |
| T-190f1 | Snapshot persistence and restore | M | ADR 0020; ADR 0016; T-190a1 |
| T-190f2 | Liability and available-credit projection | M | T-190b2–e2; T-190f1; owner overpayment/cycle decision; PV-04 |
| T-190g1 | Single-item review and durable undo | M | PV-04; T-164c/d; T-190a1–f2; ADR 0011/0016 |
| T-190g2 | Bulk review preview and grouped undo | M | PV-04; T-190g1; grouped-undo review |
| T-190h1 | Shared statement importer integration | M | T-102 completed contract/implementation; T-190f1; PV-04 |
| T-190h2 | Card statement account mapping and review | M | T-190h1; T-102; T-190a2/f1; T-100 where refunds appear; PV-04 |
| T-178b1 | Forecast contract and model comparison | M | T-178a; T-177a audit/coverage contract |
| T-178b2 | Rolling-origin evaluator | M | T-178b1; T-177a; T-177f |
| T-178b3 | Validated forecast/anomaly claims | L (split if needed) | T-178b1/b2; T-178a |
| T-178c1 | Taxonomy and synthetic corpus | M | T-178a; T-178b forecast semantics; T-190 for card-bill intent |
| T-178c2 | Typed parsing and refusal | M | T-178c1 |
| T-178c3 | Validated result selection and fixed rendering | M | T-178c1/c2; T-190/T-100/T-098 where applicable |
| T-178d1 | Offline evaluation harness | M | T-178b/c; T-177f |
| T-178d2 | Device profile and budgets | M | T-115; T-194 context; ADR 0009; evaluator/instrumentation |
| T-178d3 | Opt-in stages and kill switch | M | T-178d1/d2; T-178a–c |

### New parents (2026-10-10)

Child-level dependencies live in each brief; parents appear here once.

| Parent | Work | Depends |
|---|---|---|
| T-203 | Import flicker and speed | None |
| T-204 | UI/UX v2 and icon system | T-203 per folder; T-158c for detail children |
| T-205 | Categorisation/income gap and payee review | ADR 0036 for e–h |
| T-206 | Merge to `main`, branch deletion list | Owner action |
| T-207 | Intelligence v2 | ADR 0034/0035 for schema children; T-178c2/c3 for Ask intents |
| T-208 | Performance budgets and proxies | T-203e for f |
| T-209 | Refund attribution owner decision | Owner |
| T-210 | Test-suite speed and shards | None |
| T-211 | Category taxonomy | ADR 0036 for b/e |
| T-162b/d | Sender evidence; payroll aliases | T-205b/c/e for d |
| T-171b | Acceptance budgets | T-208l for b3 |

**Graph validation:** every listed board ID and implementation slice appears
once in this sequence. The overview graph's cross-task edges were checked
against the corresponding brief/plan Depends statements (intra-task slice
edges live only in this ledger); T-165b is not a T-100 prerequisite and is a hard
T-190b2 prerequisite through b1. T-190a2 may proceed earlier, but b1 must pass
before that slice invokes reconciliation. PV-04 precedes T-190b2/g1, and no
edge returns from T-190g to PV-04.

## Release gate summary

- T-194 remains open until the exact signed candidate is installed on the
  supported ARM64 phone and measured against its same-device baseline.
- T-177a remains open until a consented real chronological holdout has enough
  explicit labels for the predeclared metrics and the separate live/resume
  capture matrix passes on device. Its bounded source/document reconciliation
  is complete and independently reviewed; no period has been selected and
  proposed thresholds await the owner's approval or revision before labels
  are opened.
- Backup import/recovery acceptance remains deferred and uses only ADR 0019's
  isolated QA identity. Physical restore under `com.paisatrack` is forbidden.

Exact operators, thresholds and evidence formats: [release gates](release-gates.md)
and [backup import acceptance](backup-import.md).

## Not on this roadmap

- Rebuilding transaction links, expected events, or broad net semantics from
  old briefs: existing implementations must be audited and reused.
- Starting schema/migration work before an ADR and additive migration plan.
- Automatic financial inference, cloud processing, inferred currency
  conversion, or using synthetic replay as real-world acceptance.
- See the [T-100 scope note](../tasks/T-100.md#dependencies-and-readiness) for
  T-126/PV-02's boundary.
- T-130 owning O(n²) transfer work, integer-paise conversion, or the repository
  split; those are assigned to T-165b/c/d to prevent duplicate ownership.

## Open questions for owner

- Choose the consented chronological T-177a period and approve or revise its
  proposed minimum cohort and target thresholds in [release gates](release-gates.md)
  before any holdout labels are opened or the real-data contract is frozen.
- Confirm whether T-102 should ship CSV-only first, or include a second
  explicitly supported export format at launch.
- Confirm whether an ambiguous partial refund should remain completely outside
  budget net totals until the user links it, or be shown as a separate
  unlinked-credit adjustment.

## Next implementation slice

Wave 1 above. T-165b is complete ([brief](../tasks/T-165b.md)); T-177a keeps
its product priority for assistance work but no longer blocks T-205, which
uses the shipped ADR 0031 correction path.
