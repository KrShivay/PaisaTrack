# Development Rules

## Definition of done

Every feature includes implementation, tests, code documentation, and relevant
project documentation in the same change.

- Run GitNexus impact analysis before editing an existing symbol.
- Prefer additive schema migrations and preserve user data.
- Test success, failure, idempotency, and privacy-sensitive paths.
- Update architecture, schema, privacy, design, or an ADR when affected.
- Run `detect_changes()` before committing.

## Verification

Keep watched feeds bounded, aggregate full-history metrics in SQL, and batch
bulk-import pages in one database transaction. Add scale regressions whenever a
new UI surface reads transaction history.

```sh
.tooling/flutter/bin/flutter analyze --no-pub
.tooling/flutter/bin/flutter test --no-pub --concurrency=1
git diff --check
```

For Android changes:

```sh
cd android
./gradlew :app:testDebugUnitTest :paisatrack_keystore:testDebugUnitTest
```

Device-only behavior—SMS, background jobs, local models, document pickers,
performance, and accessibility—requires physical-device evidence.

CI/release acceptance also requires the Android app and Keystore Gradle unit
tests. A release artifact is invalid when it falls back to debug signing.

## Test placement

- Unit/widget/provider tests: `test/`.
- Device tests: `integration_test/`.
- Sanitized SMS fixtures: `test/fixtures/sms/<bank>/`.
- Statement fixtures: add sanitized, minimal fixtures under a dedicated
  `test/fixtures/statements/<bank>/` directory when T-102 starts.

## Future-feature test requirements

- Statements: parser mappings, malformed rows, idempotency, deduplication,
  ambiguity, and transactional rollback.
- Refunds: partial/multiple links, net totals, unlink behavior.
- Recurring calendar: reminder-vs-transaction separation, duplicate reminders,
  settlement matching, cancellation, and missed events.
- Budgets: month boundaries, excluded sources/transfers, repayments, thresholds,
  and projections.

Never commit raw SMS, real statements, full account/card identifiers, model
prompts containing personal data, or plaintext financial exports.
