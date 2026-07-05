# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

This repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
The product and technical source of truth is [PLAN.md](PLAN.md).

## Current Status

Phase 0 foundation scaffold is present, but runtime verification is blocked in this
environment because Flutter/Dart are not installed.

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
