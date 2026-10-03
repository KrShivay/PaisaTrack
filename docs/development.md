# Development Rules

## Flutter setup

The repo-local SDK lives at `.tooling/flutter`, which is gitignored and is not
included in a fresh clone or cloud checkout. CI pins Flutter **3.44.4** in
`.github/workflows/ci.yml`. Install that SDK into `.tooling/flutter` before
using the commands below; for example:

```sh
mkdir -p .tooling
git clone --depth 1 --branch 3.44.4 https://github.com/flutter/flutter.git .tooling/flutter
.tooling/flutter/bin/flutter doctor
.tooling/flutter/bin/flutter pub get
```

`flutter doctor` reports host dependencies that are missing. Android builds
and Gradle tests also need the Android SDK and the Java version configured in
CI. On Ubuntu, CI installs `libsqlcipher-dev` before running database tests;
reproduce that host dependency with `sudo apt-get update` and
`sudo apt-get install -y libsqlcipher-dev`, as in `.github/workflows/ci.yml`. The
`.tooling` path is local only and must not be committed.

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

## GitNexus

Use the GitNexus MCP when it is available. For CLI work, the ignored local
runner supports:

```sh
node .gitnexus/run.cjs status
node .gitnexus/run.cjs impact "SymbolName" --direction upstream --repo .
node .gitnexus/run.cjs detect-changes --scope all --repo .
```

If `.gitnexus/run.cjs` is absent, bootstrap GitNexus with
`bunx gitnexus@latest analyze` or use the configured MCP. Indexing may
regenerate root `AGENTS.md` and `CLAUDE.md`; review those diffs and restore the
repository's policy instructions before finishing. A stale or missing index is
not evidence that a symbol has no callers.

## Owner-machine steps

These steps need the owner's configured machine and must not block cloud code
work:

- ADB installation, physical-phone QA, SMS capture, and device-only acceptance
  require the owner's Android device and local ADB setup.
- Release builds require the gitignored
  `android/paisatrack-release.jks` and `android/keystore.properties` described
  in [release signing](release-signing.md). Never copy either into a cloud
  checkout, artifact branch, or source control.
- Codex and Luna CLI review require the owner's local installations and
  authentication. Record which checks ran; do not report an unavailable local
  review as passed.

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
