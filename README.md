# PaisaTrack

Android-first, privacy-first personal finance tracking from transactional SMS.
Parsing, categorization, analytics, and optional language-model inference run
on-device. No cloud inference path exists.

## Android release

Download the currently published [PaisaTrack 0.1.3+2007 ARM64 APK](https://raw.githubusercontent.com/KrShivay/PaisaTrack/apk-downloads/app-release-arm64.apk) (56.75 MB; 56,750,680 bytes). Its SHA-256 is `0affd549d926814082d6ff1548aefebcda768dcd0d2c1f326e5c11856daa86c3`. The production signature was verified. An in-place upgrade passed on the ARM64 phone: the installed package is `com.paisatrack`, version name `0.1.3`, effective ARM64 version code `4007`; the existing install time was preserved and the app remained foregrounded without a crash exit. A fresh encrypted backup was verified off-device before installation. Broader T-167c responsive-layout, T-176 screen-inset, and T-179a key-recovery acceptance remain open. For 64-bit ARM Android devices.

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

The next product priority is less manual transaction work: safe auto-fill,
confirmed-history learning, scoped corrections and grouped review. Grounded
insights and measured forecasts follow; optional statement/receipt evidence
adds context without inventing financial facts.

See [PLAN.md](PLAN.md), the [feature plan](docs/plans/smart-transaction-assistance.md),
the [AI report](docs/reports/grounded-ai-opportunities.md), and [TASKS.md](TASKS.md).
These are proposed changes, not a claim that the flow has shipped.

## Project documentation

- [Architecture and planning map](ARCHICTURE.md)
- [Technical architecture](docs/architecture.md)
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
