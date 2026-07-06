---
name: kotlin-native-bridge
description: >
  Use when touching anything under android/app/src/main/kotlin/com/paisatrack/,
  or any Dart file that talks to a MethodChannel/EventChannel
  (lib/capture/sms_channel.dart and friends). Use when: adding or changing
  the SMS receiver, inbox backfill reader, WorkManager jobs, notification
  action handling, or any channel contract between Kotlin and Dart.
checklist:
  - Channel name and every payload key are defined once in a Kotlin object
    AND once in a matching Dart constants file — never inline string
    literals scattered at call sites on either side.
  - Every channel payload change bumps a version field the Dart side checks;
    old payload shapes are handled or explicitly rejected, never silently
    misread.
  - SmsBroadcastReceiver.onReceive() does no blocking work — it calls
    goAsync() before touching the DB/network and always calls
    pendingResult.finish(), including on every exception path.
  - Ordered broadcast priority and abortBroadcast() usage (if any) is
    justified in a code comment — silently swallowing another app's SMS
    receiver is a support nightmare.
  - Historical inbox backfill runs off the main thread and reports progress
    incrementally — it never blocks the UI for the full 12-month read.
  - WorkManager jobs declare explicit constraints (idle + charging where the
    plan requires it) and a bounded run time; long-running work is chunked
    and resumable, not a single unbounded coroutine.
  - A JUnit contract test exists that pins the exact payload schema
    (keys + types) sent across the channel for any new/changed message type.
  - No raw SMS body crosses the channel without immediately being wrapped in
    the same RawSms-shaped payload the Dart side expects — no ad hoc maps.
---

# Kotlin ↔ Dart Native Bridge Conventions

Plan references: PLAN.md §2 (tech stack — native layer must be Kotlin),
§3 (android/ folder layout), §4 (Capture feature list), §7.9 (nightly job
order/constraints).

## 1. Channel contract conventions

Every channel (`MethodChannel` or `EventChannel`) between
`SmsChannelHandler.kt` and `lib/capture/sms_channel.dart` follows one rule:
**the schema is defined in exactly one Kotlin file and one Dart file, both
named for the channel, and nowhere else.**

```kotlin
// android/.../sms/SmsChannelContract.kt
object SmsChannelContract {
    const val CHANNEL_NAME = "com.paisatrack/sms"
    const val EVENT_CHANNEL_NAME = "com.paisatrack/sms_stream"

    // Payload version — bump when adding/removing/renaming a key.
    const val PAYLOAD_VERSION = 1

    // Keys — never use raw string literals for these at call sites.
    const val KEY_SENDER = "sender"
    const val KEY_BODY = "body"
    const val KEY_RECEIVED_AT = "receivedAt" // epoch ms, Long
    const val KEY_VERSION = "version"
}
```

```dart
// lib/capture/sms_channel_contract.dart
class SmsChannelContract {
  const SmsChannelContract._();

  static const channelName = 'com.paisatrack/sms';
  static const eventChannelName = 'com.paisatrack/sms_stream';
  static const payloadVersion = 1;

  static const keySender = 'sender';
  static const keyBody = 'body';
  static const keyReceivedAt = 'receivedAt';
  static const keyVersion = 'version';
}
```

Both files must change together in the same PR. If they drift, the JUnit
contract test (§4 below) catches it — that test is not optional.

Adding a field: bump `PAYLOAD_VERSION`/`payloadVersion` in both, add the key
to both, and make the Dart-side decoder tolerate the old version (default
the new field to `null`/a safe default) unless you've confirmed no old APK
is in the field — during development that's every version, so always be
tolerant.

## 2. SMS receiver lifecycle pitfalls

Android 8+ (API 26, our min SDK) restricts implicit broadcasts and
background execution aggressively. Concrete failure modes to avoid:

- **Doing DB/network work synchronously in `onReceive()`.** The system can
  kill the process once `onReceive()` returns; anything async you kicked
  off without `goAsync()` may never complete. Always:
  ```kotlin
  override fun onReceive(context: Context, intent: Intent) {
      val pendingResult = goAsync()
      CoroutineScope(Dispatchers.IO).launch {
          try {
              handleSms(context, intent)
          } finally {
              pendingResult.finish()
          }
      }
  }
  ```
- **Forgetting `pendingResult.finish()` on an exception path.** Wrap the
  work in `try/finally`, not `try/catch` — a swallowed exception that skips
  `finish()` leaves the system thinking your receiver is still running and
  can throw an ANR-adjacent penalty on the app.
- **Ordered broadcast assumptions.** `SMS_RECEIVED` is an ordered broadcast;
  other apps' receivers may run before or after yours depending on priority.
  Don't assume you see every SMS first, and never call `abortBroadcast()`
  unless the plan explicitly calls for suppressing delivery to other apps
  (it currently does not — PaisaTrack only reads, never blocks delivery).
- **Registering the receiver only in the manifest** for `RECEIVE_SMS` is
  correct (dynamic registration doesn't receive this broadcast reliably
  pre-Android 8 boot state); don't "helpfully" also dynamically register —
  that causes duplicate delivery.

## 3. WorkManager constraint patterns

Nightly jobs (`NightlyJobsWorker.kt`, driving `lib/background/nightly_jobs.dart`
per plan §7.9) must declare:

```kotlin
val constraints = Constraints.Builder()
    .setRequiresDeviceIdle(true)
    .setRequiresCharging(true)
    .build()

val request = PeriodicWorkRequestBuilder<NightlyJobsWorker>(1, TimeUnit.DAYS)
    .setConstraints(constraints)
    .build()
```

The worker itself enforces the plan's 3-minute hard cap and resumability:
checkpoint progress (e.g., "recurring scan done, retrain pending") in
`model_meta` or a dedicated `job_state` row so a killed/rescheduled run
picks up where it left off instead of restarting the whole pipeline.

## 4. The JUnit contract test

Every channel message type gets a test that pins the exact schema — this is
what lets Claude and Codex change either side independently without a
runtime surprise:

```kotlin
// android/app/src/test/kotlin/.../SmsChannelContractTest.kt
class SmsChannelContractTest {
    @Test
    fun `sms payload contains exactly the contracted keys`() {
        val payload = buildSmsPayload(sampleSms)
        assertThat(payload.keys).containsExactly(
            SmsChannelContract.KEY_SENDER,
            SmsChannelContract.KEY_BODY,
            SmsChannelContract.KEY_RECEIVED_AT,
            SmsChannelContract.KEY_VERSION,
        )
        assertThat(payload[SmsChannelContract.KEY_RECEIVED_AT]).isInstanceOf(Long::class.java)
    }
}
```

`containsExactly`, not `contains` — an accidental extra key (e.g. a leaked
debug field) should fail the test just as loudly as a missing one.

## Related

- `db-and-migrations` — what happens to the payload once it lands as `RawSms`.
- `sms-template-authoring` — how the Dart side turns the payload into a
  transaction.
- `testing-discipline` — Kotlin test pyramid mapping (plan §10).
