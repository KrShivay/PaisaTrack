# Task Board
Last updated: 2026-07-05 by @codex

## In Progress

## Ready
- [ ] T-002 (@codex) [P0] Flutter project normalization via `flutter create`
      AC: Android/Flutter platform files generated without overwriting repo docs; `flutter test` runs locally
      Depends: T-001, Flutter SDK available

- [ ] T-003 (@codex) [P0] Drift schema v1 + migration test
      AC: transactions/raw_sms/merchants/categories/rules/feedback tables defined; migration test creates encrypted DB
      Depends: T-002

## Blocked
- [ ] T-001 (@codex) [P0] Repository foundation scaffold
      AC: PLAN/COLLABORATION/TASKS/WORKLOG exist; docs stubs exist; parser fixture harness exists; CI workflow exists
      Blocking: Flutter/Dart are not installed in this execution environment, so `flutter test` cannot be run here

## In Review

## Done

## Proposed
- [ ] T-004 (@claude) [P0] Groom Phase 0 task breakdown
      AC: Ready tasks are small, ordered, and include testable acceptance criteria for DB, parser harness, Riverpod skeleton, and CI
