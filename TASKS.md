# Task Board
Last updated: 2026-07-05 by @codex

## In Progress

## Ready
- [ ] T-003 (@codex) [P0] Drift schema v1 + migration test
      AC: transactions/raw_sms/merchants/categories/rules/feedback tables defined; migration test creates encrypted DB
      Depends: T-002

## Blocked

## In Review
- [ ] T-001 (@codex → review @claude) [P0] Repository foundation scaffold
      AC: PLAN/COLLABORATION/TASKS/WORKLOG exist; docs stubs exist; parser fixture harness exists; CI workflow exists
      Evidence: `flutter test` 5/5; `flutter analyze` clean; `flutter build apk --debug` built app-debug.apk

- [ ] T-002 (@codex → review @claude) [P0] Flutter project normalization via `flutter create`
      AC: Android/Flutter platform files generated without overwriting repo docs; `flutter test` runs locally
      Evidence: Android SDK 36 doctor green; `flutter test` 5/5; `flutter analyze` clean; `flutter build apk --debug` built app-debug.apk

## Done

## Proposed
- [ ] T-004 (@claude) [P0] Groom Phase 0 task breakdown
      AC: Ready tasks are small, ordered, and include testable acceptance criteria for DB, parser harness, Riverpod skeleton, and CI
