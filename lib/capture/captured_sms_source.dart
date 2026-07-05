import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/raw_sms.dart';

/// Source of sanitized SMS events emitted by the Android host.
abstract interface class CapturedSmsSource {
  /// Broadcast stream of newly captured raw SMS messages.
  Stream<RawSms> messages();
}

/// Abstraction over the platform event channel so tests can fake it directly.
abstract interface class CapturedSmsChannel {
  /// Returns the native event stream payloads.
  Stream<Object?> receiveBroadcastStream();
}

/// Event-channel implementation backed by Android.
class PlatformCapturedSmsChannel implements CapturedSmsChannel {
  const PlatformCapturedSmsChannel({
    EventChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const EventChannel _defaultChannel = EventChannel(
    'com.paisatrack/sms_events',
  );

  final EventChannel _channel;

  @override
  Stream<Object?> receiveBroadcastStream() {
    return _channel.receiveBroadcastStream();
  }
}

/// Converts platform event payloads into domain [RawSms] instances.
class PlatformCapturedSmsSource implements CapturedSmsSource {
  const PlatformCapturedSmsSource({
    CapturedSmsChannel channel = const PlatformCapturedSmsChannel(),
  }) : _channel = channel;

  final CapturedSmsChannel _channel;

  @override
  Stream<RawSms> messages() {
    return _channel.receiveBroadcastStream().map(_decodeRawSms);
  }

  RawSms _decodeRawSms(Object? event) {
    if (event is! Map<Object?, Object?>) {
      throw StateError('SMS event payload must be a map.');
    }

    final id = event['id'];
    final sender = event['sender'];
    final body = event['body'];
    final receivedAtEpochMillis = event['receivedAtEpochMillis'];
    if (id is! String ||
        sender is! String ||
        body is! String ||
        receivedAtEpochMillis is! int) {
      throw StateError('SMS event payload is missing required fields.');
    }

    return RawSms(
      id: id,
      sender: sender,
      body: body,
      receivedAt: DateTime.fromMillisecondsSinceEpoch(
        receivedAtEpochMillis,
        isUtc: true,
      ),
    );
  }
}

/// Injectable source for production capture and fake-channel tests.
final capturedSmsSourceProvider = Provider<CapturedSmsSource>((ref) {
  return const PlatformCapturedSmsSource();
});
