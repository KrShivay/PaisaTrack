# Current Handoff

## 2026-10-03 — Roadmap planning and docs cleanup (no code)

- Added proposed plans: [roadmap](docs/plans/roadmap.md) (graph, sub-slice
  ledger, next slice), [release gates](docs/plans/release-gates.md) (T-194,
  T-177a holdout), [risk register](docs/plans/risk-register.md),
  [backup import](docs/plans/backup-import.md) (deferred),
  [credit-card accounting](docs/plans/credit-card-accounting.md) + ADR 0020
  (Proposed) + briefs T-190a1–h2, and
  [grounded-AI validation](docs/plans/grounded-ai-validation.md) (T-178b–d).
  Groomed briefs T-100/101/102/098/130; board points to them; nothing Ready.
- Docs: [index](docs/README.md), [ADR index](docs/decisions/README.md) (0013
  unused, next 0021), `scripts/check_doc_links.py` (clean), archived the
  2026-08 value review, restored the missing `## Ready` heading.
- Reviews: T-190 and roadmap each passed independent Luna review after
  revision (T-190 R2 approve-with-changes, applied; roadmap R3 accept).
- Next code slice: T-165b (+ stale `transfer_leg` cleanup) as a parallel data
  lane; T-177a holdout stays the product-priority gate. Owner decisions are
  listed in the roadmap and T-190 plan. No app tests run (docs only).
  The T-177 R1 entry is in Git history (`239c2d2`).

## 2026-10-02 — T-177 R3 rules and Ask on resolved payee identity

- A rule made on `swiggy@ybl` never fired for a text-only "SWIGGY" SMS even
  after the user linked both, and Ask matched merchants by raw substring
  ("ola" hit "Coca Cola"; relabeled payees vanished; VPA-only rows were
  missed). Corrections on rows with an exact persisted merchant link
  (`confidence_json.merchant.src` exact/new/user) now create `merchant_id`
  rules; precedence is exact VPA → merchant_id → exact name → legacy. The
  correction sweep covers both linked rows and exact VPA/name matches among
  unlinked history. Ask resolves the phrase to an identity set (labels,
  aliases, payee evidence) with whole-phrase matching, asks which payee when
  several match (suggestions re-resolve), and answers "no matching payee"
  instead of a ₹0 total. No schema change; rolling back leaves merchant_id
  rules inert.
- Impact: `RuleRepository`/`TransactionRepository` CRITICAL. Verified:
  analyzer clean, full suite 1136/1136, intelligence/data/enrichment/capture
  559/559 under America/New_York. Three review rounds. Release 2013 details
  stay in docs/release-signing.md.

## 2026-10-02 — T-177 R2 one payee identity across capture paths

- History import and catch-up never resolved merchants (user labels did not
  apply to imported rows) and a ≥0.92 embedding match silently merged
  payees. All three paths now share one resolver (user VPA alias → user name
  alias → exact canonical name → deterministic merchant); similar names only
  suggest. A shared `PayeeKey` strips a tested noise list for lookup while
  stored evidence, rules and aliases keep the existing key contract (v20
  re-key planned in docs/tasks/T-177.md). Phone-like UPI ids are never
  auto-stored. Imports use one merchant snapshot per run, staged per SMS and
  merged only after that SMS commits, and skip embeddings. Verified:
  analyzer clean, full suite 1124/1124, enrichment/data/capture 408/408
  under America/New_York; three review rounds. Commit `f730857`.
