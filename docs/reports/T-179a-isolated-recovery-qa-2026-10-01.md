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

## Physical gate remains open

At the last device preflight, `adb devices -l` listed no connected device. No
APK was installed; no phone-side app, database, key, permission, backup, or
restore operation was performed. The following acceptance has not been
observed: cold-launching the QA wrapper into the real `KeyLossScreen`, choosing
the staged synthetic archive through Android SAF, restoring it, and verifying
the sentinel rows from a new process. Keystore alias/wrapped-preference
continuity also remains unproven. Keep T-179a open for that physical run.

When the phone is available, run the two integration targets in order with
`ORG_GRADLE_PROJECT_recoveryQa=true` and
`--dart-define=PAISATRACK_RECOVERY_QA=true`: first
`integration_test/recovery_qa_fixture_test.dart`, then launch the QA package's
ordinary entrypoint, stage only the emitted synthetic `.ptrack` into Downloads,
observe the real KeyLossScreen, select that file through SAF, and finally run
`integration_test/recovery_qa_verify_test.dart` in a fresh process. Never run
the key-reset harness under `com.paisatrack` or grant SMS permissions to the QA
package.
