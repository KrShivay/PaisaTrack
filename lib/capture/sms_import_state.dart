import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Version 1 was the legacy three-month import. Version 2 scans full history.
/// Existing installs therefore perform one automatic catch-up after upgrade.
const smsHistoryImportVersion = 2;

/// Cursor saved after a fully processed inbox page so an interrupted automatic
/// import resumes instead of rescanning the complete inbox from newest again.
class SmsImportCheckpoint {
  const SmsImportCheckpoint({
    required this.beforeEpochMillis,
    required this.beforeId,
  });

  final int beforeEpochMillis;
  final int beforeId;
}

/// Persists the newest completed automatic SMS-history import version.
abstract interface class BackfillMarker {
  Future<int> completedVersion();

  Future<SmsImportCheckpoint?> checkpoint();

  Future<void> saveCheckpoint(SmsImportCheckpoint checkpoint);

  Future<void> markCompleted(int version);

  /// Clears the marker when all app data is deliberately reset.
  Future<void> reset();
}

class PlatformBackfillMarker implements BackfillMarker {
  const PlatformBackfillMarker({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/sms_backfill',
  );

  final MethodChannel _channel;

  @override
  Future<int> completedVersion() async {
    return await _channel.invokeMethod<int>('completedBackfillVersion') ?? 0;
  }

  @override
  Future<SmsImportCheckpoint?> checkpoint() async {
    final payload = await _channel.invokeMethod<Object?>('backfillCheckpoint');
    if (payload == null) return null;
    if (payload is! Map<Object?, Object?>) {
      throw const FormatException('Invalid SMS import checkpoint payload');
    }
    if (payload case {
      'beforeEpochMillis': final int beforeEpochMillis,
      'beforeId': final int beforeId,
    }) {
      return SmsImportCheckpoint(
        beforeEpochMillis: beforeEpochMillis,
        beforeId: beforeId,
      );
    }
    throw const FormatException('Invalid SMS import checkpoint values');
  }

  @override
  Future<void> saveCheckpoint(SmsImportCheckpoint checkpoint) async {
    await _channel.invokeMethod<void>(
      'saveBackfillCheckpoint',
      <String, Object?>{
        'beforeEpochMillis': checkpoint.beforeEpochMillis,
        'beforeId': checkpoint.beforeId,
      },
    );
  }

  @override
  Future<void> markCompleted(int version) async {
    await _channel.invokeMethod<void>(
      'markBackfillVersion',
      <String, Object?>{'version': version},
    );
  }

  @override
  Future<void> reset() async {
    await _channel.invokeMethod<void>('resetBackfillVersion');
  }
}

final backfillMarkerProvider = Provider<BackfillMarker>((ref) {
  return const PlatformBackfillMarker();
});
