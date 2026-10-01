# T-179a isolated recovery QA status — 2026-10-01

## Implemented and checked

- Recovery QA is gated behind the Gradle property `recoveryQa=true`. It creates
  only the debug package `com.paisatrack.recoveryqa`; malformed values and QA
  release/bundle tasks fail configuration. The default debug package remains
  `com.paisatrack` and contains no QA identity classes or channel.
- The QA-only manifest uses the distinct launcher label “PaisaTrack Recovery
  QA” and removes `READ_SMS`, `RECEIVE_SMS`, and `SmsReceiver`. A QA-only
  `Application` rejects the wrong package/build identity before Flutter starts.
  The QA Dart entrypoint and each sensitive integration-test entry also await a
  QA-only native identity RPC before provider, file, or Keystore work. Missing
  RPCs and identity mismatches fail closed.
- The prepare integration target creates a synthetic SQLCipher legacy database
  and encrypted `.ptrack` file in the QA package, confirms its generation-key
  registry is empty before resetting only the QA legacy key, and checks that
  the synthetic encrypted file family remains byte-identical. The verify
  target uses the production `appDatabaseProvider` to reopen the restored
  generation and check synthetic sentinel rows, archive/file hashes, SQLCipher
  integrity, and foreign-key integrity. A SHA-256 digest tracks the synthetic
  replacement legacy passphrase value across restore; it does not prove
  Android Keystore alias or wrapped-preference continuity.

The final launcher APK was built from the production startup path through the
QA wrapper:

| Item | Evidence |
|---|---|
| Package / version | `com.paisatrack.recoveryqa`, 0.1.3 / code 4012 |
| APK | `build/app/outputs/flutter-apk/app-debug.apk` |
| Preserved review copy | `/tmp/paisatrack-t179a-recoveryqa-final.apk` |
| SHA-256 | `5e354dc6fefec7f41eb2d7280f37ec426ec6a327ffb2d86c05b2fe8f303022b4` |
| Size | 245,684,950 bytes |
| Debug certificate SHA-256 | `f43ef54d1d5cd4e925565d40c082bf91db31b8c55ba0f3ebca644bf0a619774d` |
| Merged manifest | `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml` |

Independent review confirmed the QA package, debug signer, distinct launcher,
SMS-free merged manifest, QA-only RPC/Application, and preflight ordering. A
normal debug build retained `com.paisatrack` and excluded QA classes. The
default release manifest was checked in a metadata-only Gradle task using
non-secret placeholder signing values because this worktree has no release
signing file; no release APK was produced. QA release/bundle requests and
malformed property values fail closed. With QA enabled, `:app:assembleDebug`
passes, while aggregate `build` and `assemble` stop before execution when their
app task graphs include release tasks. The guard is scoped to `:app:` so
release-named dependency tasks do not block the isolated debug build.

## Validation

- `flutter test --no-pub`: 962 passed.
- `flutter analyze --no-pub`: no issues.
- `dart format --output=none --set-exit-if-changed` on the 10 touched Dart
  files: no changes required.
- Android Gradle debug unit tests: 31 app tests and 10 Keystore tests passed,
  zero failures or errors.
- Both isolated prepare and verify integration targets compiled into the QA
  debug variant. Their device-side execution is not included in these counts.
- Gradle guard checks: QA `:app:assembleDebug` succeeded; QA aggregate `build`
  and `assemble` rejected app release task graphs before packaging; QA
  `:app:bundleRelease` rejected during configuration.
- `git diff --check`: clean.

## Physical acceptance run — 2026-10-01

Device: owner Motorola edge 50 pro (`ro.serialno` `ZD222KTYNC`, Android 16)
over wireless ADB. Every phase was built with
`ORG_GRADLE_PROJECT_recoveryQa=true`, `--dart-define=PAISATRACK_RECOVERY_QA=true`
and `--target-platform android-arm64`. Prepare and the launcher came from
`8df44e8`; the final verify re-run came from `28a9498` plus the marker fix.
`git diff --name-only 8df44e8 28a9498` touches only SMS capture, calendar and
dashboard code: no recovery, database, crypto, Android or pubspec file. All
builds reported `com.paisatrack.recoveryqa` version code 2012 (`aapt2` and
`dumpsys`), signed by debug certificate
`f43ef54d1d5cd4e925565d40c082bf91db31b8c55ba0f3ebca644bf0a619774d`. The
2012 code differs from the 4012 recorded for the earlier preserved artifact in
the table above; that APK no longer exists, so it was neither reused nor
compared. Launcher APK SHA-256 for this run:
`5350c18e2bfbe09f4fd5d9d056e1a1c514fba0b0ff81d14302a5b92f63799dfd`.

Evidence retained outside the repository: command logs, the KeyLossScreen
and post-restore screenshots, and an owner/QA package snapshot taken after the
final phase (`dumpsys`: owner appId 10438, code 4012, unchanged timestamps; QA
appId 11017, code 2012, zero SMS permission lines). Fail-closed identity
behaviour rests on the earlier reviewed host/build checks; this physical run
exercised only the matching-identity path.

Safety: `flutter test` reinstalls by uninstalling the *built* package if an
install fails, so the launcher APK was built and inspected with `aapt2` and
`apksigner` before any device phase (package `com.paisatrack.recoveryqa`, no
`READ_SMS`/`RECEIVE_SMS`, launcher label "PaisaTrack Recovery QA"). Device
phases used `--no-uninstall`; the launcher used plain `adb install -r`. The QA
package (appId 11017) has no SMS permission requested or granted; the owner
package (appId 10438) stayed at code 4012 with `firstInstallTime`
`2026-09-26 22:20:54` and `lastUpdateTime` `2026-10-01 00:31:39` before the first and after
the final phase. No owner data, key, backup or setting was read or changed; font
scale (1.0) and rotation (0) were never modified.

| Phase | Observation |
|---|---|
| Prepare (`recovery_qa_fixture_test.dart`) | Passed; `RECOVERY_QA_PREPARED` archive SHA-256 `f0ca6f37b227d2029c4e7851ee072c6a8f74ae3ac08166fc0ea807f37f21d5a6`, one synthetic transaction and payment source |
| Stage | Archive pulled with `run-as`, hash re-checked, pushed to `Download/t179a-synthetic-recovery.ptrack` (hash matched on device) |
| Cold launch (ordinary QA entrypoint) | `am start -W`: `LaunchState: COLD`; production `KeyLossScreen` ("Encryption Key Unavailable", "Restore backup") |
| SAF selection and restore | Synthetic test passphrase entered; Restore opened `com.google.android.documentsui` PickActivity (focused-window dump); navigated to Downloads and selected the single UI-dump match for the synthetic file. The app routed to Home showing the synthetic sentinel row. The picker screenshot was discarded because its Recent view showed owner account names; the picker step is operator-observed from window/UI dumps |
| Fresh-process verify (`recovery_qa_verify_test.dart`) | App force-stopped, no process; passed. `legacyDatabaseFamilyMatches` true, `preservedLegacyCopyMatches` true, `archiveSha256Matches` true, `qaLegacyPassphraseContinuitySha256Matches` true, sentinel rows 1/1, `integrity_check` ok, 0 foreign-key issues, 0 staging generations |

The first verify run asserted the hash maps with deep `expect` (both passed)
but emitted `false` for the two family-match marker fields because Dart
`Map ==` is identity. The marker now uses `recoveryQaHashMapsEqual`
(unit-tested); the verify phase was re-run from a fresh process with the fixed
harness and reported `true` for both.

Cleanup: the staged synthetic file was removed from Downloads. The QA package
remains installed with synthetic data only; uninstalling it is safe and does
not affect `com.paisatrack`.

Not attested, by design: Android Keystore alias and wrapped-preference
continuity. The passphrase digest proves only that the synthetic replacement
legacy passphrase value was unchanged by restore.
