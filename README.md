# PaisaTrack

Android-first, privacy-first personal finance tracking from transactional SMS.
Parsing, categorization, analytics, and optional language-model inference run
on-device. No cloud inference path exists.

## Current product

- Live SMS capture, resumable page-batched history import, and bounded
  open/resume catch-up with recent-gap recovery.
- Template, generic, and optional local-LLM transaction extraction.
- Encrypted SQLCipher storage with Android Keystore-backed keys.
- Manual entry, transaction editing, rules, feedback, and duplicate suppression.
- Categories, merchant resolution, recurring detection, forecasts, insights,
  SQL-aggregated dashboard analytics, and a grounded local assistant.
- User labels for merchant/VPA aliases and masked payment-source management,
  including owned-transfer and analytics-exclusion rules.
- Encrypted backup/import and database/key reset.

The current Bloom worktree is not production-ready. Release blockers and the
verified feature matrix are tracked in
[Product status](docs/product-status.md); notably, native notification/model
state is not yet covered by Delete everything.

## Future development

The selected roadmap focuses on:

1. Physical-device acceptance for responsive startup and live/resume SMS capture.
2. Statement import and reconciliation.
3. Reimbursement and refund tracking.
4. A recurring-payment calendar, including upcoming-payment SMS detection.
5. Monthly category budgets.
6. Release hardening: app lock, performance, accessibility, widget, and
   distribution work.

See [PLAN.md](PLAN.md) for feature contracts and [TASKS.md](TASKS.md) for the
future-only backlog. Completed and review-only history is intentionally omitted;
Git history is the archive.

## Project documentation

- [Architecture](docs/architecture.md)
- [Product status](docs/product-status.md)
- [Schema](docs/schema.md)
- [Privacy](docs/privacy.md)
- [Design system](docs/design-system.md)
- [Development rules](docs/development.md)
- [Durable decisions](docs/decisions/)
- [Active work](TASKS.md)

## Local setup

```sh
.tooling/flutter/bin/flutter pub get
.tooling/flutter/bin/flutter analyze --no-pub
.tooling/flutter/bin/flutter test --no-pub
```

Android unit tests:

```sh
cd android
./gradlew :app:testDebugUnitTest :paisatrack_keystore:testDebugUnitTest
```

Do not commit raw SMS, statements, account identifiers, or unsanitized exports.
