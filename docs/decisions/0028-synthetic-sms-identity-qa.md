# ADR 0028 — Permission-free physical SMS identity verification

Status: Accepted for engineering verification, 2026-10-04.

## Context

T-201 reports that live and history capture hash different timestamp columns.
Android documents `DATE` as received time and `DATE_SENT` as sent time. Existing
RecoveryQA removes SMS permissions and the receiver; owner inbox access is
prohibited. Physical verification must precede a timestamp fix.

## Decision

Use the existing isolated debug-only RecoveryQA identity with a synthetic-only
native probe and integration test. Exercise production inbox conversion through
an injected cursor/query boundary and production live conversion with synthetic
PDU input where supported. The default production query remains the platform
resolver. The probe must not grant SMS permissions, query a real inbox, capture
owner logs, launch the owner app, or change production identity semantics.

Verify RecoveryQA identity before calling the probe. Return only fixed synthetic
inputs/results or counts; preserve its debug-only packaging guards. Use existing
dependencies. A synthetic native execution on the physical Android runtime is
evidence of conversion/identity behavior, not carrier delivery or the owner's
messaging provider. Those remaining boundaries must be stated explicitly.

## Consequences

The query seam supports deterministic native tests without private data. A
subsequent identity fix still requires a compatibility contract for stored IDs,
pagination, ingestion and provenance. No source-record rewrite, schema change,
ownership/accounting approval or APK publication is authorized by this ADR.

## Native fallback after test-connection failure

The Flutter integration runner installed and launched RecoveryQA, but its
forwarded WebSocket closed before loading the probe test. A QA-only explicit
custom action may invoke the same fixed native probe from Activity lifecycle
dispatch. Repeat the existing package/application ID, debug build, debuggable
flag and resource gates before invocation. Keep the method-channel path.
Emit only the fixed synthetic result marker with selected safe booleans and
the known receive-delay difference; never log message content, hash IDs, the
full result map or exception text. Read only that QA process/tag's output.

Android framework lifecycle dispatch is an unindexed external caller; manifest
source corroborates it. This fallback can prove native conversion on the
physical runtime, but does not turn a failed Flutter integration run into a
passing test or validate carrier/provider delivery. Repairing the test
connection remains the proper fix for that runner limitation.

Sources: [Android SMS columns](https://developer.android.com/reference/android/provider/Telephony.TextBasedSmsColumns)
and [AOSP Messaging implementation](https://android.googlesource.com/platform/packages/apps/Messaging/+/master/src/com/android/messaging/sms/MmsUtils.java).
