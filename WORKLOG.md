# Current Handoff

## 2026-10-03 — T-167j host implementation in review (device gate open)

- Home back now honors the active tab's `maybePop` and vetoes, retains all four
  tab Navigators, returns non-Home roots to Home, and uses an accessible
  two-second Home exit confirmation without popping an enclosing route.
  Predictive Android transitions are scoped to the active uncovered tab;
  inactive/covered tab tickers are disabled, and programmatic tab state follows
  taps and PageView swipes. ADR 0022 records the behavior.
- Regression evidence: initial focused cases 0/4; programmatic Activity request
  → back Home → repeated Activity request also failed before provider sync.
  Current focused suite 18/18, full combined Flutter suite 1,259/1,259, and
  touched transaction/review/repository/shell suites in `America/New_York`
  351/351; analyzer, formatter, documentation links, and diff checks pass.
  The SQLCipher migration test ran in the full suite.
- On the isolated API 36 Recovery QA app, the pre-fix Activity-root back gesture
  exited to the owner app; after the fix, the identical gesture returns to Home
  and keeps Recovery QA foreground. No owner data was inspected. Physical IME,
  predictive-cancel, and three-button acceptance remain open; APK publishing
  remains open. The earlier user-authorized 0.1.8+2017 install is verified:
  code 4017, package `com.paisatrack`, last-update time 2026-10-03 21:49:42,
  first-install time unchanged at 2026-09-26 22:20:54, and its base APK matched
  that build's signed artifact hash and byte count. A cold launch
  returned successfully; WhatsApp was foreground afterward, so no claim is made
  that PaisaTrack remained foreground. No owner UI, logs, or rows were read.
  That installed artifact predates T-199's max-payload QR sizing correction.
  The final same-version 0.1.8+2017 arm64 artifact is installed and verified:
  code 4017, last-update time 2026-10-03 22:10:40, first-install time
  unchanged at 2026-09-26 22:20:54, and pulled base APK SHA-256 matches the
  signed artifact. No post-install UI interaction was performed.
- Follow-ups: owner-run T-167j IME/predictive checks and the existing T-176 /
  T-167c device gates; consented T-177a holdout/period decision; keep T-194 on
  `codex/apk-size-trial`; APK publishing remains open.
  Host acceptance moved T-167j to In Review, not Done.

## 2026-10-03 — T-199 host implementation in review

- Transaction details and Sort now show a shared QR action only for a valid,
  explicitly stored VPA. The review DTO carries VPA separately from merchant
  identity; the static URI contains only `pa`, a safe `pn`, and `cu=INR`. It
  performs no lookup or payment launch. Square modules use a quantized render
  size to preserve the four-module quiet zone.
- Verification: missing-action regression fails at the expected UI assertion;
  max-valid payload sizing regression failed at 247.5dp before the fix and now
  passes at 288dp with four-module quiet margins; focused QR/detail/Sort/
  repository tests 53/53; full Flutter suite 1,259/1,259;
  touched transaction/review/repository/shell suites in `America/New_York`
  351/351; analyzer clean; formatter unchanged; 142 Markdown links and
  `git diff --check` pass. GitNexus staged scan: 20 files, 57 symbols, 5
  affected flows, medium risk, with no partial/truncated result notice. The
  refreshed repository index reports 405 flows but warns that its global
  entrypoint/callee inventory is capped; absent global flows are not proof of
  no callers.
- Independent decoder verified the synthetic QR at 960/320/256 pixels and
  the max-input QR at 864×864 pixels. Both decode to the expected static UPI
  fields and have at least four modules of white quiet zone on every side.
  T-167j native-back root-exit regression also passed on the isolated
  API 36 QA app. On-device transaction detail QR display, scan, and back-to-
  detail behavior passed. Sort card/list device QA remains open: a route switch
  missed its first tap during settling, and the synthetic fixture row now shows
  the Transport category; the cause is unconfirmed. No owner rows were
  inspected. The earlier on-device detail scan used the pre-correction QR
  geometry; the encoded contents are unchanged. The final max-input host decode
  verified the 256/64 VPA and 120-emoji payee with at least four white modules
  on each side. Final artifact:
  `.dart_tool/qa/paisatrack-v0.1.8-arm64-release.apk`, 57,144,364 bytes,
  SHA-256 `38549d00295432512b05401c97bb6bb682f5915832c1a91091edd247fdc86a41`,
  production signer suffix `9163`. The same-version code 4017 in-place update
  is verified installed: package `com.paisatrack`, last-update time
  2026-10-03 22:10:40, first-install time unchanged at 2026-09-26 22:20:54,
  and the pulled base APK SHA-256 exactly matches the artifact hash above.
  APK publication remains open.

## 2026-10-04 — T-200 confirmation repair installed; owner UI gate open

- One `Confirm details` action replaces the independent status and parse
  controls. It shows saved amount/currency, direction, payee, and category;
  eligible status/evidence writes are atomic and do not change financial fields
  or train category prediction. Receipt-based Undo preserves earlier feedback
  and refuses stale edits. ADR 0024 records the contract.
- Independent review passed. Full suite 1,270/1,270; encrypted-schema migration
  executed without skips; touched repository/transaction suites in
  `America/New_York` 275/275; analyzer clean; formatter five files unchanged;
  Markdown links 144 files and diff checks pass. The initial full run exposed
  two consumer render expectations, now corrected and verified.
- Signed arm64 0.1.9+2018 compiled and installed in place (effective code 4018).
  Last update 2026-10-04 01:59:00; first install remains 2026-09-26 22:20:54.
  Installed base APK equals the signed 57,144,364-byte artifact SHA-256
  `8f6e43bb50423b254f33e1cd50ed3d3037ee55761639649d8e1b21d4c34a55b6`.
  Signature, ZIP integrity, alignment, and arm64-only libraries pass.
- Owner-screen confirmation/Undo acceptance remains open; no private screens,
  records, SMS, database, or logs were inspected. T-200 remains In Review.
  QR Sort card/list and native back device gates stay open. Paused T-167b work
  remains in both stashes; resume the newer `paused T-167b before T-200` stash
  by applying it, preserving the older stash. No APK publication is authorized.

- Final GitNexus all-change analysis: 12 files, 36 symbols, zero reported
  affected flows, LOW risk; no partial/truncated result flag. The global
  inventory limitation above remains; source review and regression tests
  cover the dynamically dispatched UI path.
