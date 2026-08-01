import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SmsFilterCounters {
  const SmsFilterCounters({
    required this.liveFilterRejected,
    required this.batchFilterRejected,
    required this.liveUnknownSender,
    required this.batchUnknownSender,
  });

  const SmsFilterCounters.zero()
      : liveFilterRejected = 0,
        batchFilterRejected = 0,
        liveUnknownSender = 0,
        batchUnknownSender = 0;

  final int liveFilterRejected;
  final int batchFilterRejected;
  final int liveUnknownSender;
  final int batchUnknownSender;

  factory SmsFilterCounters.fromPayload(Object? payload) {
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('Invalid SMS filter counters payload');
    }
    return SmsFilterCounters(
      liveFilterRejected: _readCount(payload, 'liveFilterRejected'),
      batchFilterRejected: _readCount(payload, 'batchFilterRejected'),
      liveUnknownSender: _readCount(payload, 'liveUnknownSender'),
      batchUnknownSender: _readCount(payload, 'batchUnknownSender'),
    );
  }

  static int _readCount(Map<Object?, Object?> payload, String key) {
    final value = payload[key];
    if (value is! int || value < 0) {
      throw FormatException('Invalid SMS filter counter: $key');
    }
    return value;
  }
}

class PlatformSmsFilterDiagnostics {
  const PlatformSmsFilterDiagnostics({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/sms_diagnostics',
  );

  final MethodChannel _channel;

  Future<SmsFilterCounters> readCounters() async {
    final payload = await _channel.invokeMethod<Object?>('filterCounters');
    return SmsFilterCounters.fromPayload(payload);
  }
}

final smsFilterCountersProvider = FutureProvider.autoDispose<SmsFilterCounters>(
  (ref) => const PlatformSmsFilterDiagnostics().readCounters(),
);
