# Documentation index

Use [TASKS.md](../TASKS.md) for unfinished implementation work, [PLAN.md](../PLAN.md) for future ordering, and [product status](product-status.md) for verified behavior. [Architecture](architecture.md), [schema](schema.md), and [privacy](privacy.md) are the technical constraints. This index records the current Markdown set; `current` means maintained reference or active proposal, `historical` means retained evidence, and `historical-pointer` means a completed-task brief reduced to a Git-history pointer.

## Start here

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [README.md](../README.md) | Repository entry point linking to canonical product/release status | current | docs |
| [ARCHICTURE.md](../ARCHICTURE.md) | Navigation stub to canonical architecture docs | current; navigation only | docs |
| [PLAN.md](../PLAN.md) | Future outcomes and delivery order | current | planning |
| [TASKS.md](../TASKS.md) | Executable unfinished-work board | current | planning |
| [WORKLOG.md](../WORKLOG.md) | Rolling handoff, latest session evidence | current | session handoff |
| [COLLABORATION.md](../COLLABORATION.md) | Shared task lifecycle and definition of done | current | process |
| [docs/README.md](README.md) | This documentation inventory | current | docs cleanup |

## Process

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [development.md](development.md) | Local development and verification conventions | current | process |
| [tasks/README.md](tasks/README.md) | Task-brief index and completed-pointer map | current | docs cleanup |

## Architecture and reference

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [architecture.md](architecture.md) | Current application and data architecture | current | architecture |
| [schema.md](schema.md) | Current schema summary and migration pointers | current | schema |
| [privacy.md](privacy.md) | Data handling, retention, and privacy constraints | current | privacy |
| [product-status.md](product-status.md) | Verified behavior and unresolved acceptance gates | current | product status |
| [design-system.md](design-system.md) | Bloom design tokens and component conventions | current | UI |
| [assistant-nlq.md](assistant-nlq.md) | Grounded assistant behavior contract | current | T-178 |
| [sms-templates.md](sms-templates.md) | Parser template registry and provenance reference | current | capture |
| [seed-assets.md](seed-assets.md) | Seed asset inventory | current | assets |
| [release-signing.md](release-signing.md) | Android signing and release procedure/evidence | current; release gates remain tracked separately | release |

## ADRs

See the [decision index](decisions/README.md) for status and numbering, including the intentionally unused 0013.

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [decisions/README.md](decisions/README.md) | ADR index, status, and numbering notes | current | docs cleanup |
| [decisions/0001-flutter-local-first.md](decisions/0001-flutter-local-first.md) | Flutter local-first app decision | maintained ADR; status not explicit | architecture |
| [decisions/0002-no-cloud-services.md](decisions/0002-no-cloud-services.md) | No-cloud decision | maintained ADR; status not explicit | privacy |
| [decisions/0003-dedup-and-counterparty.md](decisions/0003-dedup-and-counterparty.md) | Duplicate and counterparty identity decision | accepted ADR | capture |
| [decisions/0004-automated-agent-handoff.md](decisions/0004-automated-agent-handoff.md) | Agent handoff process decision | current ADR | process |
| [decisions/0005-fixture-provenance-and-parse-trust.md](decisions/0005-fixture-provenance-and-parse-trust.md) | Fixture provenance and trust promotion | current ADR | capture |
| [decisions/0006-in-app-assistant.md](decisions/0006-in-app-assistant.md) | Local assistant decision | current ADR | assistant |
| [decisions/0007-on-device-embedding-model.md](decisions/0007-on-device-embedding-model.md) | Embedding model decision | current ADR | T-050 |
| [decisions/0008-bounded-encrypted-backups.md](decisions/0008-bounded-encrypted-backups.md) | Encrypted backup limits and streaming envelope | current ADR | backup |
| [decisions/0009-litert-lm-runtime-and-qwen3.md](decisions/0009-litert-lm-runtime-and-qwen3.md) | On-device LLM runtime/model | current ADR | T-075 |
| [decisions/0010-sql-payee-identity-index.md](decisions/0010-sql-payee-identity-index.md) | SQL payee identity index | current ADR | T-117 |
| [decisions/0011-evidence-backed-assistance.md](decisions/0011-evidence-backed-assistance.md) | Evidence-backed assistance proposal and accepted-in-part scope | current ADR | T-177, T-178 |
| [decisions/0012-generation-based-database-recovery.md](decisions/0012-generation-based-database-recovery.md) | Database recovery proposal | proposed ADR | recovery |
| [decisions/0014-ask-category-query-scopes.md](decisions/0014-ask-category-query-scopes.md) | Ask category-query scope | maintained ADR; status not explicit | assistant |
| [decisions/0015-durable-sms-disposition.md](decisions/0015-durable-sms-disposition.md) | Durable SMS disposition | maintained ADR; status not explicit | T-185 |
| [decisions/0016-backup-domain-state-and-restore-order.md](decisions/0016-backup-domain-state-and-restore-order.md) | Backup domain state and restore order | maintained ADR; status not explicit | backup |
| [decisions/0017-source-currency-fidelity.md](decisions/0017-source-currency-fidelity.md) | Source currency fidelity | current ADR | T-187 |
| [decisions/0018-capture-decision-version.md](decisions/0018-capture-decision-version.md) | Capture-decision provenance version | current ADR | T-177a |
| [decisions/0019-isolated-recovery-qa-identity.md](decisions/0019-isolated-recovery-qa-identity.md) | Isolated identity for physical recovery QA | current ADR | T-179a |
| [decisions/0020-credit-card-accounting.md](decisions/0020-credit-card-accounting.md) | Credit-card accounting boundaries | proposed ADR | T-190 |

## Plans

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [plans/smart-transaction-assistance.md](plans/smart-transaction-assistance.md) | Proposed assistance rollout using existing components | current proposal | T-177 |
| [product-quality-review.md](product-quality-review.md) | Recurring product-quality review cadence | current procedure; referenced by T-172 | T-172 |
| [parser-generic-fallback.md](parser-generic-fallback.md) | Generic parser contract and rejection gates | current reference; corroborated by parser tests | capture |
| [sms-intelligence-design.md](sms-intelligence-design.md) | Capture/intelligence design still referenced by open board tasks | current proposal/reference | T-133, T-143 |
| [ui-gaps-and-redesign.md](ui-gaps-and-redesign.md) | UI conformance design still referenced by open task briefs | current proposal/reference | T-149, T-150, T-151, T-154 |

### Roadmap and planning (2026-10, proposed)

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [plans/roadmap.md](plans/roadmap.md) | Sequenced roadmap: dependency graph, critical path, sub-slice ledger, next slice | current proposal; independently reviewed | planning |
| [plans/release-gates.md](plans/release-gates.md) | Exact T-194 APK trial and T-177a holdout gates | current proposal; gates open | T-194, T-177a |
| [plans/risk-register.md](plans/risk-register.md) | Consolidated roadmap risk register | current | planning |
| [plans/backup-import.md](plans/backup-import.md) | Deferred backup import/restore acceptance (isolated QA identity only) | current proposal; deferred | T-170b, PV-05 |
| [plans/credit-card-accounting.md](plans/credit-card-accounting.md) | Credit-card accounting scenario map and model | current proposal; independently reviewed | T-190 |
| [plans/grounded-ai-validation.md](plans/grounded-ai-validation.md) | Forecast ranges, Hinglish intents, evaluation gates | current proposal | T-178b–d |

## Specs

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [specs/trends-inbox.md](specs/trends-inbox.md) | Trends inbox lifecycle and retention contract | current specification | T-178 |

## Task briefs

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [tasks/T-117.md](tasks/T-117.md) | SQL payee identity index | historical; complete brief retained | T-117 |
| [tasks/T-131.md](tasks/T-131.md) | Numeric trust boundary | historical-pointer | T-131 |
| [tasks/T-132.md](tasks/T-132.md) | Lifecycle state split | historical-pointer | T-132 |
| [tasks/T-133.md](tasks/T-133.md) | Admission and quarantine | current; board work remains | T-133 |
| [tasks/T-134.md](tasks/T-134.md) | Financial events and link graph | historical-pointer | T-134 |
| [tasks/T-135.md](tasks/T-135.md) | Net-spending contract | historical-pointer | T-135 |
| [tasks/T-136.md](tasks/T-136.md) | Counterparty identity | historical-pointer | T-136 |
| [tasks/T-137.md](tasks/T-137.md) | Merchant clustering | historical-pointer | T-137 |
| [tasks/T-138.md](tasks/T-138.md) | Expected events | historical-pointer | T-138 |
| [tasks/T-139.md](tasks/T-139.md) | Subscription and EMI classification | historical-pointer | T-139 |
| [tasks/T-140.md](tasks/T-140.md) | Categorization ladder; production gaps route to T-177 | historical-pointer | T-140, T-177 |
| [tasks/T-141.md](tasks/T-141.md) | Anomaly precision | historical-pointer | T-141 |
| [tasks/T-142.md](tasks/T-142.md) | Explain-this-charge | historical-pointer | T-142 |
| [tasks/T-143.md](tasks/T-143.md) | Corpus, shadow mode, and metrics; brief/board status conflict remains open | current; unresolved reconciliation | T-143 |
| [tasks/T-144.md](tasks/T-144.md) | Play declaration and consent | historical-pointer | T-144 |
| [tasks/T-145.md](tasks/T-145.md) | Full-screen category picker | historical-pointer | T-145 |
| [tasks/T-146.md](tasks/T-146.md) | Category icons | historical-pointer | T-146 |
| [tasks/T-147.md](tasks/T-147.md) | Source message view | historical-pointer | T-147 |
| [tasks/T-148.md](tasks/T-148.md) | Category row tap target | historical-pointer | T-148 |
| [tasks/T-149.md](tasks/T-149.md) | Local profile | current; board work remains | T-149 |
| [tasks/T-150.md](tasks/T-150.md) | Assistant prompt catalogue | historical; completed brief retained | T-150 |
| [tasks/T-151.md](tasks/T-151.md) | Ask design conformance | current; remaining children open | T-151 |
| [tasks/T-152.md](tasks/T-152.md) | Full-screen sheet route | historical-pointer | T-152 |
| [tasks/T-153.md](tasks/T-153.md) | Sort cursor and recoverable skip | stale/conditional; board says recheck only if still needed | T-153 |
| [tasks/T-154.md](tasks/T-154.md) | Edit from Sort | current; remaining child open | T-154 |
| [archive/tasks/T-155.md](archive/tasks/T-155.md) | Threshold constant consolidation proposal | archived; stale and unboarded | T-155 |
| [tasks/T-156.md](tasks/T-156.md) | Sheet and dialog presentation consolidation | current; remaining children open | T-156 |
| [tasks/T-157.md](tasks/T-157.md) | Riverpod boundary hardening | historical; completed work mapped in archive | T-157 |
| [tasks/T-158.md](tasks/T-158.md) | Transaction detail screen split | current; remaining children open | T-158 |
| [tasks/T-159.md](tasks/T-159.md) | Correction/detail regression coverage | current; completed children retained with future child | T-159 |
| [tasks/T-160.md](tasks/T-160.md) | Activity pagination correctness | current; child tasks remain on board | T-160 |
| [tasks/T-161.md](tasks/T-161.md) | SMS capture outcome counts and retry | current; child tasks remain on board | T-161 |
| [tasks/T-162.md](tasks/T-162.md) | Salary-credit ingestion coverage | current; child tasks remain on board | T-162 |
| [tasks/T-172.md](tasks/T-172.md) | Product-value review evidence boundary and waiver | historical; closed with waiver | T-172 |
| [tasks/T-177.md](tasks/T-177.md) | Smart transaction assistance | current; active | T-177 |
| [tasks/T-178.md](tasks/T-178.md) | Grounded analysis, forecasts, and assistant | current proposal; Backlog | T-178 |
| [tasks/T-098.md](tasks/T-098.md) | Category budgets brief | current; Backlog, not Ready | T-098 |
| [tasks/T-100.md](tasks/T-100.md) | Refund/reversal accounting brief | current; Backlog, not Ready | T-100 |
| [tasks/T-101.md](tasks/T-101.md) | Expected-payment calendar brief | current; Backlog, not Ready | T-101 |
| [tasks/T-102.md](tasks/T-102.md) | Statement import brief | current; Backlog, not Ready | T-102 |
| [tasks/T-130.md](tasks/T-130.md) | Residual coupling brief | current; narrowed | T-130 |
| [tasks/T-165b.md](tasks/T-165b.md) | Indexed owned-transfer reconciliation and stale-edge cleanup | historical; completed/reviewed brief retained | T-165b, T-190b1 |
| [tasks/T-190.md](tasks/T-190.md) | Credit-card accounting phased briefs | current; Backlog, not Ready | T-190 |
| [tasks/T-189.md](tasks/T-189.md) | Readable Ask prompt list | historical; completed/reviewed brief retained | T-189 |
| [tasks/T-193.md](tasks/T-193.md) | Legacy currency repair | historical; physical acceptance recorded in `385e056`, UNDO-1 fixed in `58af0a4` | T-193 |
| [tasks/T-194.md](tasks/T-194.md) | Compressed ARM64 packaging trial | current; In Progress | T-194 |
| [tasks/T-195.md](tasks/T-195.md) | Keep source SMS provenance | current; Ready | T-195 |
| [tasks/T-196.md](tasks/T-196.md) | Transaction details card | current; Ready | T-196 |
| [tasks/T-197.md](tasks/T-197.md) | Activity scroll position after edit | current; Ready | T-197 |
| [tasks/T-198.md](tasks/T-198.md) | Readable payee names | current; Ready | T-198 |

## Reports

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [reports/T-176-physical-ask-ime-2026-09-30.md](reports/T-176-physical-ask-ime-2026-09-30.md) | Physical Ask keyboard acceptance result | historical evidence; gate failed/remains open | T-176 |
| [reports/T-176-T-167c-emulator-matrix-2026-10-02.md](reports/T-176-T-167c-emulator-matrix-2026-10-02.md) | Emulator layout matrix and first-pass results | current evidence; physical gates remain open | T-176, T-167c |
| [reports/T-177a-capture-provenance.md](reports/T-177a-capture-provenance.md) | Synthetic replay/provenance and integration reconciliation | current evidence; physical/holdout gates open | T-177a |
| [reports/T-179a-isolated-recovery-qa-2026-10-01.md](reports/T-179a-isolated-recovery-qa-2026-10-01.md) | Isolated physical recovery QA evidence | historical evidence; result recorded | T-179a |
| [reports/T-193-currency-repair-qa-2026-10-01.md](reports/T-193-currency-repair-qa-2026-10-01.md) | Currency repair synthetic and physical QA evidence | historical evidence; T-193 accepted and removed from the board | T-193 |
| [reports/grounded-ai-opportunities.md](reports/grounded-ai-opportunities.md) | Existing capabilities and proposed grounded AI work | current evaluation report | T-178 |
| [reports/release-v2012-owner-phone-install-2026-10-01.md](reports/release-v2012-owner-phone-install-2026-10-01.md) | Owner-phone install observation for v2012 | historical evidence; not task acceptance | release |

## Archive

| File | Purpose | Status | Owner task |
|---|---|---|---|
| [archive/README.md](archive/README.md) | Archive policy and replacement pointers | current index | docs cleanup |
| [archive/planning-cleanup-2026-09.md](archive/planning-cleanup-2026-09.md) | Compact mapping for completed briefs and superseded queues | historical pointer | docs cleanup |
| [archive/litert-lm-migration-plan.md](archive/litert-lm-migration-plan.md) | Superseded runtime/model migration plan | superseded | T-075 |
| [archive/decisions/0008-on-device-llm-model.md](archive/decisions/0008-on-device-llm-model.md) | Earlier ADR 0008 model pin superseded by current backup ADR 0008 and ADR 0009 | superseded | T-075 |
| [archive/bloom/bloom-feature-design-addendum.md](archive/bloom/bloom-feature-design-addendum.md) | Original Bloom feature design addendum | historical | UI |
| [archive/bloom/bloom-feature-migration-audit.md](archive/bloom/bloom-feature-migration-audit.md) | Original Bloom migration audit | historical | UI |
| [archive/reviews/2026-07-25-full-codebase-review.md](archive/reviews/2026-07-25-full-codebase-review.md) | Dated codebase review snapshot | historical | review |
| [archive/reviews/product-value-review-2026-08.md](archive/reviews/product-value-review-2026-08.md) | Product-value review and follow-on register | archived historical review; current summary in product-status | T-172 |
| [archive/reviews/T-108-branch-code-review.md](archive/reviews/T-108-branch-code-review.md) | Resolved branch review snapshot | historical | T-108 |
| [archive/reviews/T-108-branch-review-round-2.md](archive/reviews/T-108-branch-review-round-2.md) | Resolved follow-up review snapshot | historical | T-108 |
| [archive/reviews/T-108-branch-review-round-3.md](archive/reviews/T-108-branch-review-round-3.md) | Resolved follow-up review snapshot | historical | T-108 |

## Archive decisions

The proposed cleanup candidates remain in place. Open board tasks and task briefs still use the SMS-intelligence and UI design docs as sources; T-172 and product-status still link the product review and quality procedure; parser tests and `lib/capture/generic_transaction_parser.dart` retain the generic parser contract as current reference. See [archive policy](archive/README.md).
