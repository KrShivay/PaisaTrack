# PaisaTrack — Project Status Report

Reviewed 2026-07-12 by @codex against PLAN.md, TASKS.md, the implementation,
tests, and feature documentation.

## 1. Current phase

PaisaTrack is in **Phase 3 (Intelligence)**. Phase 2 passed its exit review.
The Phase 3 feature set is implemented. Its remaining gate is the evidence-based
Phase 3 exit review (T-064), assigned to @human because it requires real usage.

The shipped intelligence path now includes:

- on-device merchant embeddings and similarity-based merchant resolution;
- a pure-Dart local classifier trained from correction feedback;
- adaptive per-category decision thresholds;
- recurring, anomaly, forecast, and deterministic insight engines plus screens;
- a hidden model-metrics screen and atomic correction learning loop.

The usable Phase 4 feature slice is also complete in parallel:
feature-flagged MediaPipe inference, integrity-checked resumable model download,
app-private storage/delete controls, typed fallback behavior, and strict JSON
schema validation; a grounded in-app money assistant; validated unmatched-SMS
extraction; and aggregate-only monthly narratives that reject model-authored
numbers.

## 2. Next work

1. T-064: @human runs the Phase 3 exit review after two weeks of real feedback and
   verify classifier auto-label/correction metrics, recurring dates, and genuine
   anomaly/forecast evidence.
2. Device QA the Phase 4 feature flags: model download/delete, offline
   unmatched-SMS extraction, assistant refusals, and monthly narrative output.
3. T-067 remains blocked on public Kotak/Central Bank fixture gathering.

## 3. Architecture and privacy

PaisaTrack remains local-first. Android filters and captures SMS; Dart parses
and enriches normalized records; encrypted Drift/SQLCipher stores local state;
and Riverpod exposes repositories and screens. Merchant embeddings, classifier
training, adaptive thresholds, insights, and LLM inference stay on-device.

Raw SMS is not a classifier feature and is never sent to a service. The optional
LLM model is downloaded only by explicit Settings action; prompts and responses
remain on-device, and the model can be deleted from Settings.

## 4. Review status

T-051, T-052, T-053, T-054, T-062, T-063, T-075, and T-076 passed review on
2026-07-12 after fixing the review-band alias trust escalation, per-category
classifier gating, the 30-new-feedback trainer gate, corrected-label threshold
accounting/idempotence, and classifier/answered-ask metrics attribution.

The live source of truth remains [TASKS.md](TASKS.md); detailed verdicts and
verification evidence are in [docs/tasks-archive.md](docs/tasks-archive.md) and
[WORKLOG.md](WORKLOG.md).

## 5. Known gaps

- T-052's previously noted fuzzy free-text category-name resolution remains
  separate from the classifier work; typoed ask-now answers can still fall back
  to Other.
- T-064 requires real usage evidence and cannot be closed by synthetic tests.
- T-067 requires externally sourced, provenance-recorded fixtures and must not
  be fabricated.

## 6. Bottom line

Phase 3 implementation is feature-complete. @human's real-usage T-064 review
still needs closure; the usable Phase 4 feature slice is implemented under the
explicit gate exception. T-084/T-085 need one post-release-flag verification
rerun, followed by physical-device/offline QA.
