# Release and evaluation gates

Status: proposed gate definitions for T-194 and T-177a. These definitions do
not claim either gate has passed. They preserve the unfinished acceptance in
[T-194](../tasks/T-194.md), [T-177](../tasks/T-177.md), and the
[capture provenance report](../reports/T-177a-capture-provenance.md).

## T-194 — compressed APK physical trial

### Candidate and baseline

- Candidate under review: T-194 signed ARM64 artifact, SHA-256
  `cb9a3deb34207ea4b9aef251f7ce411166e7ac59cc4d5cff3690844691672e29`,
  26,180,416 bytes, package `com.paisatrack`, version `0.1.3`, effective code
  `4011`, production signer. The packaging-only control must come from the
  same source/toolchain with legacy JNI packaging disabled; compare the six
  library content hashes before use.
- The owner's installed production build is newer than the 4011 candidate
  (latest published build: [release signing](../release-signing.md)). Never
  uninstall or downgrade the owner's production app to install the candidate. Preflight must use
  a supported ARM64 test phone without `com.paisatrack` data, or create a new
  paired candidate/control with an effective code greater than the installed
  version. If neither is available, gate remains open.
- Candidate identity, signature, APK hash, archive integrity, `zipalign`,
  manifest `extractNativeLibs=true`, six library paths, and source/control
  library hashes must match the T-194 record. Existing APK-size threshold
  (`<= 27,000,000` bytes) is already met by the recorded artifact; recheck the
  exact bytes installed.

### Physical procedure and thresholds

Owner runs the trial on the supported ARM64 phone; a second reviewer checks
artifact identity and the aggregate evidence. No app publication is part of
this gate.

1. Record phone model, Android/API version, ABI, OS build, battery range,
   thermal state, app version, artifact hash, and the storage-measurement tool.
   Keep these identical for baseline and candidate runs.
2. Install the same-source default-packaging control. Measure package code/app
   storage separately from user data and cache. Run at least 30 cold starts per
   arm: force-stop, launch the same entry route, and record `am start -W` total
   and time-to-first-frame from a local monotonic trace. Do not clear app data
   between trials.
3. Replace the control with the candidate using an in-place update, repeat the
   same storage and at least 30 cold-start measurements, then restore the
   control or uninstall only this empty test installation. Never remove or
   alter owner data.
4. **Pass** when installed app/code storage increases by at most 25,000,000
   bytes versus control; for each cold-start metric, the upper endpoint of the
   bootstrap 95% confidence interval for the candidate-minus-control median is
   no greater than the larger of 10% of the control median or 250 ms. Compute
   the interval from 10,000 bootstrap resamples of each arm using a recorded
   seed. All launches must succeed; no crash/fatal native-load marker may be
   observed; artifact/library identity checks must pass. Report absolute values
   and deltas. p95 is descriptive only and does not determine pass/fail. The
   projected extraction increase is about 23,069,324
   bytes; this projection is not device evidence.
5. Any failed launch, threshold breach, candidate identity mismatch, or missing
   repeatable measurement fails the trial. Keep the published packaging config
   unchanged and retain T-194 as open pending a new reviewed trial.

### Evidence format

Attach one Markdown/JSON table with at least 30 baseline and 30 candidate launch
samples per cold-start metric, median and bootstrap 95% CI for the median
difference, resample count and seed, descriptive p95, app/code storage and user data/cache reported separately, device
and OS metadata, APK SHA-256s, signer, version codes, library hashes, install
result, crash check and pass/fail reason. Redact device serial, account names,
notifications and unrelated app data. Do not attach a full `dumpsys`, logcat,
screen recording or screenshots containing user content. Owner performs; QA
reviewer verifies the artifact/evidence. No private finance data is required.

## T-177a — real chronological holdout and physical capture

### Holdout selection and run

Owner runs the evaluation locally on the supported phone using an explicitly
consented historical period that occurs strictly after a frozen model/rule/
decision version. The holdout is chronological and is not used to tune rules or
thresholds. Freeze the evaluation contract and cohort definitions before
opening the holdout. Existing selected feedback and the four-row synthetic
replay are not holdout evidence. If existing local labels are insufficient,
leave the gate open; do not lower the cohort minimum or claim a pass.

No evaluation period or cohort has been selected. Before opening any holdout
labels, the owner must choose and consent to the chronological period and
approve or revise the proposed cohort floor, metrics, and thresholds below.
Record that decision in the frozen evaluation contract; this document does not
imply owner approval.

Use the local replay/evaluation flow from
`test/support/capture_replay_report.dart` only if the owner-approved run can
provide the held-out aggregate without exporting transaction/message rows. If
an implementation change is needed to run on device or emit aggregate-only
results, groom that as a separate task first. Do not copy raw SMS, references,
merchant labels, amounts, transaction IDs, or database/archive files out of the
phone. Never request a backup passphrase.

### Metrics and thresholds

Record aggregate counts only, split by capture path (live/history/resume),
month/cohort, and decision mode where each bucket has enough rows:

- captured, parseable, predicted, abstained, and explicitly labeled counts;
- correct and incorrect decisions among explicit labels; precision numerator,
  denominator and 95% Wilson interval;
- decision coverage, explicit-label coverage, and user decisions per 100
  captured rows;
- missing source-span count, unversioned/unsupported-decision count, and
  percentage of persisted amount/date/reference facts backed by source evidence
  or explicit user edits;
- false financial-exclusion count and conflicts/unknown outcomes.

**Pass for a cohort considered for automation** requires all of the following:

- At least 200 eligible explicit holdout decisions in each rollout cohort
  considered for automation, with no tuning on those records. An under-sized
  cohort remains suggestion-only and unvalidated.
- At least 98% precision among explicitly labeled automatic category
  assignments and 95% Wilson lower bound at least 95%, per rollout cohort.
- At least 50% fewer user decisions per 100 eligible transactions than the
  same-period current-flow baseline, with no precision decrease.
- Zero known false accounting exclusions in the release acceptance set and
  100% evidence/user-edit backing for persisted amount/date/reference facts.
- Physical device checks separately pass for live delivery and app-resume
  catch-up, including the known-SMS boundary and no duplicate rows. These
  checks do not replace the aggregate holdout metrics.

These are proposed release thresholds, not owner-approved acceptance criteria.
The proposed minimum holdout count is made explicit here; the owner may approve
or revise it before the period and contract are frozen. An insufficient sample,
missing chronology, unversioned rows, or any known false exclusion keeps
automation disabled for that cohort; it is not a pass.

### Privacy and evidence

Run and label on-device. The owner controls selection and retains raw evidence
locally. The review artifact contains only cohort/path labels, counts, rates,
confidence intervals, threshold result, app/build/model/rule versions and
device/API class. No raw or normalized transaction rows, SMS body, VPA, account
identity, merchant/category label, exact amount, date, transaction/SMS ID,
database or backup leaves the device. Report suppresses any group smaller than
10 and combines it into `other/suppressed`; the overall sample sufficiency count
may still be reported. Store only the aggregate report in the repository after
privacy review. The owner runs; an independent reviewer checks the frozen
contract, aggregate calculations and pass/fail result.

## Gate status

- T-194: physical candidate install/storage/cold-start comparison is unverified
  and open. The owner phone runs the latest published build in
  [release signing](../release-signing.md); preflight incompatibility with the 4011 candidate must be resolved.
- T-177a: the synthetic provider/replay milestone and bounded source/document
  reconciliation are complete and independently reviewed. The current source
  and ADR 0018 support `capture-decision-v2`; old/malformed/unsupported rows
  remain excluded. Real holdout and physical live/resume evidence remain open.
  No chronological period has been selected and proposed thresholds await
  owner approval or revision before contract freeze.
