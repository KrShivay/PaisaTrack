# Current Handoff

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

## 2026-10-02 — T-177 R1 corrections take effect; rules stay precise

- A second category correction for the same payee never took effect for
  future captures (each correction inserted a rule; matching returned the
  oldest). Corrections now replace the rule for that identity; undo restores
  the previous rule, swept rows and feedback in one transaction (all or
  nothing). New merchant rules match the exact normalized payee key (a
  `SWIGGY` rule no longer categorizes "Swiggy Instamart"); schema v19
  (data-only) tags existing merchant rules `merchant_legacy`, which keep the
  old word-boundary fallback only when no exact rule matches; pre-v19
  backups are normalized on restore via an authenticated header marker.
  History/catch-up rule hits get the live rule status, while their `asked`
  decisions clamp to needs_review so old rows never flood the Ask queue.
  Capture-decision provenance v2 records the category source (ADR 0018).
- Impact: `findMatch` CRITICAL, `PayeeIdentityKey` HIGH. Verified: analyzer
  clean, full suite 1106/1106, enrichment/data/capture 390/390 under
  America/New_York. Three review rounds. Follow-ups: undo should skip rows
  edited after the correction; revert a learned alias on undo. The T-188
  entry is in Git history (`7f3a58f`).
