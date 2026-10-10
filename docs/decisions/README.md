# Decision index

ADRs record durable technical decisions. Status wording below follows each file; “no Status field” means the document body has no explicit status line.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-flutter-local-first.md) | Flutter local-first app | no Status field; status unverified |
| [0002](0002-no-cloud-services.md) | No cloud services | no Status field; status unverified |
| [0003](0003-dedup-and-counterparty.md) | Explicit duplicate links and counterparty VPA | accepted (2026-07-07) |
| [0004](0004-automated-agent-handoff.md) | Automated agent handoff | accepted |
| [0005](0005-fixture-provenance-and-parse-trust.md) | Fixture provenance and parse-trust promotion | accepted |
| [0006](0006-in-app-assistant.md) | In-app local assistant | accepted |
| [0007](0007-on-device-embedding-model.md) | Pinned on-device embedding model | accepted |
| [0008](0008-bounded-encrypted-backups.md) | Bounded encrypted backup envelopes | accepted |
| [0009](0009-litert-lm-runtime-and-qwen3.md) | LiteRT-LM runtime and Qwen3 | accepted |
| [0010](0010-sql-payee-identity-index.md) | SQL payee identity index | accepted for T-117 |
| [0011](0011-evidence-backed-assistance.md) | Evidence-backed transaction assistance and AI | accepted-in-part; see ADR body for remaining proposal scope |
| [0012](0012-generation-based-database-recovery.md) | Generation-based database recovery | proposed |
| 0013 | Intentionally unused (draft superseded by 0016); do not reuse | no current ADR |
| [0014](0014-ask-category-query-scopes.md) | Ask category query scopes | no Status field; status unverified |
| [0015](0015-durable-sms-disposition.md) | Durable SMS disposition | no Status field; status unverified |
| [0016](0016-backup-domain-state-and-restore-order.md) | Backup domain state and restore order | no Status field; status unverified |
| [0017](0017-source-currency-fidelity.md) | Source currency fidelity | accepted for T-187 |
| [0018](0018-capture-decision-version.md) | Capture decision version | accepted; v2 contract |
| [0019](0019-isolated-recovery-qa-identity.md) | Isolated recovery QA identity | accepted for T-179a harness |
| [0020](0020-credit-card-accounting.md) | Credit-card accounting boundaries | Proposed; owner accepted product defaults 2026-10-10; no schema approved |
| [0021](0021-retain-source-sms-provenance.md) | Retain source SMS provenance; unlinked SMS expire after 7 days | Accepted (owner decision) |
| [0022](0022-scoped-predictive-back.md) | Scope predictive back to the visible tab | Accepted for T-167j; physical Android verification pending |
| [0023](0023-static-upi-qr.md) | Render a static local UPI QR from stored VPA evidence | Accepted for T-199 implementation |
| [0024](0024-unified-transaction-detail-confirmation.md) | Unify transaction-detail status and parse confirmation | Accepted for T-200 implementation |
| [0025](0025-category-memory-suggestions.md) | Gated exact-payee category suggestions from confirmed history | Implemented and independently reviewed for T-177b-S1; production rollout remains gated |
| [0026](0026-read-only-refund-preview.md) | Read-only refund preview from persisted evidence | Accepted for T-100a-S1 preparation only; no persistence, period policy or schema approved |
| [0027](0027-read-only-card-source-audit.md) | Separate read-only card source audit route | Accepted for T-190a1 host audit only; no ownership, accounting or schema approved |
| [0028](0028-synthetic-sms-identity-qa.md) | Permission-free physical SMS identity verification | Accepted for engineering verification |
| [0029](0029-capture-evidence-corrections.md) | Conservative capture correctness repairs | Accepted for T-201 bounded fixes |
| [0030](0030-sms-identity-timestamp-compatibility.md) | Sent-time SMS identity with legacy compatibility | Accepted for T-201 capture repair |
| [0031](0031-recurring-and-correction-integrity.md) | Recurring projections and guarded category correction | Accepted for T-201 fixes |
| [0032](0032-recurring-intent-and-supporting-sms.md) | Per-transaction recurring intent and supporting SMS links (schema v20) | Accepted (owner request) |
| [0033](0033-integer-paise-amounts.md) | Integer minor-unit money (expand/contract migration) | Accepted (owner 2026-10-10); T-165c pending |
| [0034](0034-sms-facts-store.md) | Source-faithful SMS facts store; narrow ADR 0021 retention amendment | Accepted (owner 2026-10-10); T-207 pending |
| [0035](0035-dashboard-layout-store.md) | Dashboard layout and local interaction-count store | Accepted (owner 2026-10-10); T-207 pending |
| [0036](0036-explicit-payee-decisions-and-cue-rules.md) | Explicit payee decisions and direction-aware cue rules | Accepted (owner 2026-10-10); no schema; T-205/T-211 pending |

ADR 0013 was present only in snapshot commit `8800ddd`; its accepted backup decision is represented by ADR 0016. It was never part of the current ADR sequence. The duplicate number 0008 is deliberate in the surviving archive: [archived on-device LLM model pin](../archive/decisions/0008-on-device-llm-model.md) was superseded by ADR 0009, while the current [ADR 0008](0008-bounded-encrypted-backups.md) covers encrypted backups. Do not renumber either file.

ADR 0020 is the Proposed credit-card-accounting draft. Schema version numbers
in ADRs 0033–0035 are provisional ([allocation rule](../schema.md#planned-additive-areas)). ADR 0022 records the
T-167j predictive-back decision.
