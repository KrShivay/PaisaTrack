# Current Handoff

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

## 2026-10-02 — Release 0.1.4+2013 published

- Signed ARM64 APK from `7c1d1d0`: 56,947,112 bytes, SHA-256 `c22bac44…8ac4`,
  code 4013, production signer. Installed in place on the owner phone
  (firstInstallTime unchanged, installed hash matched), cold launch 550 ms
  with Home/Trends inbox rendering and no app fatal. Published on
  `apk-downloads` as `ad6bb48` (remote blob verified). Details in
  docs/release-signing.md. Next build: Home greeting copy should say "same
  days last month"; physical UNDO-1 and T-176/T-167c landscape/2× rechecks.
  The T-193 entry is in Git history (`385e056`).
