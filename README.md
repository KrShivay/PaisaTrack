# PaisaTrack

Android-first, privacy-first personal finance tracking from transactional SMS.
Parsing, categorization, analytics, and optional language-model inference run
on-device. No cloud inference path exists.

## Android release

See [product status](docs/product-status.md) for the current artifact and open release gates, and [release signing](docs/release-signing.md) for the signing procedure.

## Current product

See [product status](docs/product-status.md) for verified behavior, the feature matrix, and limitations. Do not infer acceptance from this overview.

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
