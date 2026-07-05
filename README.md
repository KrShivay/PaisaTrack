# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

This repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
The product and technical source of truth is [PLAN.md](PLAN.md).
Feature work must include matching tests and documentation; see
[docs/development.md](docs/development.md).

## Current Status

Phase 0 foundation work is in progress. The repo uses a repo-local Flutter SDK,
and local verification is currently working: `flutter analyze`, `flutter test`,
and `flutter build apk --debug` have all passed during Phase 0 work. Host tests
skip the encrypted Drift migration when SQLCipher is unavailable in the VM; the
Android SQLCipher migration has been device-tested separately on
motorola_edge_50_pro.

## Local Setup

This repo currently uses a repo-local Flutter SDK at `.tooling/flutter`.
If your shell does not have Flutter on `PATH`, run commands through that SDK:

```sh
.tooling/flutter/bin/flutter pub get
.tooling/flutter/bin/flutter test
.tooling/flutter/bin/flutter analyze
.tooling/flutter/bin/flutter build apk --debug
```

No raw SMS data should be committed. Use sanitized fixtures under
`test/fixtures/sms/<bank>/`.
