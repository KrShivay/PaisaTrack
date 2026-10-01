# T-193 source-currency repair QA — 2026-10-01

## Procedure; physical run pending

This procedure creates only synthetic records inside the isolated
`com.paisatrack.recoveryqa` package. It uses the production encrypted database
provider and key path. The QA manifest removes SMS permissions and the incoming
SMS receiver; no SMS access is requested or needed.

Set the SDK path and device serial for the operator's phone:

```sh
export PATH="$PWD/.tooling/flutter/bin:$PATH"
export ORG_GRADLE_PROJECT_recoveryQa=true
export DEVICE_ID='<device-serial>'
```

1. Prepare the database and the durable onboarding-completion setting through
   the QA-only fixture target:

   ```sh
   flutter test --no-pub -d "$DEVICE_ID" \
     integration_test/currency_repair_qa_fixture_test.dart \
     --dart-define=PAISATRACK_RECOVERY_QA=true
   ```

   Confirm the `CURRENCY_REPAIR_QA_PREPARED` marker contains transaction ID
   `t193_currency_repair_qa_transaction`, amount `1234.5`, expected applied
   values `INR`/`₹`, and expected undone values `null`/`null`.

2. Build the ordinary QA launcher from the production startup path, then
   preserve its APK before integration targets overwrite the standard output:

   ```sh
   flutter build apk --debug --target-platform android-arm64 \
     -t lib/recovery_qa/main.dart \
     --dart-define=PAISATRACK_RECOVERY_QA=true
   mkdir -p .dart_tool/qa
   cp build/app/outputs/flutter-apk/app-debug.apk \
     .dart_tool/qa/paisatrack-t193-currency-repair-launcher.apk
   adb install -r .dart_tool/qa/paisatrack-t193-currency-repair-launcher.apk
   adb shell monkey -p com.paisatrack.recoveryqa 1
   ```

   The launcher should open directly to Home without an SMS prompt.

3. In Activity, open **Synthetic Currency QA** / **1,234.50**, open the
   transaction detail, choose **Review INR from SMS**, inspect the non-mutating
   preview, then explicitly apply it.

4. For an applied-state check, run a fresh integration-test process now:

   ```sh
   flutter test --no-pub -d "$DEVICE_ID" \
     integration_test/currency_repair_qa_verify_test.dart \
     --dart-define=PAISATRACK_RECOVERY_QA=true \
     --dart-define=CURRENCY_REPAIR_QA_EXPECTED_STATE=applied
   ```

   Confirm the `CURRENCY_REPAIR_QA_VERIFIED` marker reports `INR`, `₹`, amount
   `1234.5`, and that the transient UI undo is unavailable in this fresh
   process.

5. To exercise UI apply and undo together, prepare a fresh QA fixture and
   repeat steps 1–3. If an applied-state check was run first, remove only the
   isolated QA package (`adb uninstall com.paisatrack.recoveryqa`) before
   preparing again. After applying INR, confirm the updated amount in detail
   and tap **Undo** in the toast before it expires. Then run the fresh-process
   verify command with `CURRENCY_REPAIR_QA_EXPECTED_STATE=undone`. Confirm both
   currency fields are null and `sourcePreviewAvailable` is true. If a separate
   applied-state check is also needed, run that on its own fixture before the
   UI undo rehearsal.

The requested same-run order “verify(applied), then undo in UI” cannot complete
with the current product behavior: transaction detail exposes Undo through a
10-second in-memory toast, and a fresh-process check clears that token. The
two-state UI rehearsal therefore verifies the applied amount in detail, taps
Undo immediately, then uses a fresh process to verify the undone database
state.

The repair service intentionally does not persist a repair-history log, and the
Undo toast exists only in the active UI process. The verify marker reports that
fact, whether retained source evidence still reconstructs a preview, and the
undo state visible to a fresh process. Supporting the exact verify(applied) →
UI undo order needs a separately designed durable undo affordance. Physical UI
acceptance has not yet been performed.
