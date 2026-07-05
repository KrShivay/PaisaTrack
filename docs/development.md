# Development Rules

## Definition of Done

Every feature must ship with tests, code documentation, and project
documentation in the same change.

- Tests must prove the user-visible behavior, data contract, migration, parser
  path, or integration point added by the feature.
- Code documentation must describe public APIs, providers, repositories,
  services, parsers, database helpers, and any non-obvious domain logic using
  Dart `///` comments.
- Project documentation must explain the new behavior, configuration, privacy
  impact, schema change, workflow, or manual verification steps introduced by
  the feature.
- If a feature cannot reasonably include automated tests, document the reason
  and add manual verification evidence in `WORKLOG.md`.
- If a feature does not require code comments or project documentation beyond
  existing docs, update the relevant task or `WORKLOG.md` entry with that
  decision and why.

This rule applies to app features, infrastructure changes, parser/template
behavior, database changes, CI changes, and user-facing assets.

## Where To Put Tests

- Unit tests live under `test/` beside the feature area they exercise.
- Widget/provider tests live under `test/` and should use fakes or in-memory
  databases when possible.
- Device-only checks live under `integration_test/` and must include manual
  execution notes when CI cannot run them.
- SMS parser fixtures must be sanitized and stored under
  `test/fixtures/sms/<bank>/`. Use `SmsFixtureRunner` from
  `test/fixtures/sms_fixture_runner.dart` to scan fixture pairs and compare
  parser output with expected JSON.

## Where To Put Documentation

- Code comments belong directly above the public class, method, function, enum,
  provider, or field they explain.
- Product and architecture decisions belong in `PLAN.md` or `docs/`.
- Schema details belong in `docs/schema.md`.
- Privacy-sensitive behavior belongs in `docs/privacy.md`.
- Durable technical decisions belong in `docs/decisions/` as ADRs.
- Coordination, evidence, and one-off manual verification belong in
  `WORKLOG.md`.

## Code Documentation Style

- Use `///` for public Dart APIs and domain types.
- Explain intent, invariants, edge cases, privacy/security assumptions, and
  accepted value ranges.
- Prefer short comments before complex private logic only when the reason is not
  obvious from the code.
- Do not add comments that simply restate the identifier or assignment.
- Keep generated files such as `*.g.dart` untouched.

## CI Guardrails

CI runs `dart run build_runner build --delete-conflicting-outputs` and fails if
`lib/data/db/database.g.dart` changes, so Drift schema edits must commit their
generated code. CI also runs `flutter analyze` and `flutter test`.

`integration_test/encrypted_database_migration_test.dart` requires an Android
device or emulator with SQLCipher support. Until CI has a device runner, execute
that test manually and record the device evidence in `WORKLOG.md`.
