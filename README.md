# PaisaTrack

Android-first, privacy-first expense tracking from transactional SMS.

This repository follows the two-agent workflow in [COLLABORATION.md](COLLABORATION.md).
The product and technical source of truth is [PLAN.md](PLAN.md).

## Current Status

Phase 0 foundation scaffold is present, but runtime verification is blocked in this
environment because Flutter/Dart are not installed.

## Local Setup

Install Flutter stable, then run:

```sh
flutter pub get
flutter test
```

No raw SMS data should be committed. Use sanitized fixtures under
`test/fixtures/sms/<bank>/`.
