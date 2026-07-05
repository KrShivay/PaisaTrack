import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/db/database_provider.dart';
import '../data/models/raw_sms.dart';
import 'captured_sms_source.dart';
import 'permissions/sms_permission.dart';
import 'permissions/sms_permission_provider.dart';
import 'sms_ingestion.dart';

/// Reads historical transactional SMS from the device inbox for backfill.
///
/// The interface lets providers and tests supply inbox messages without a real
/// platform channel or device.
abstract interface class SmsInboxReader {
  /// Returns filter-approved inbox messages received at or after [since].
  Future<List<RawSms>> readSince(DateTime since);
}

/// Method-channel implementation backed by the Android host.
class PlatformSmsInboxReader implements SmsInboxReader {
  const PlatformSmsInboxReader({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/sms_backfill',
  );

  final MethodChannel _channel;

  @override
  Future<List<RawSms>> readSince(DateTime since) async {
    final payloads = await _channel.invokeMethod<List<Object?>>(
      'readInbox',
      <String, Object?>{
        'sinceEpochMillis': since.millisecondsSinceEpoch,
      },
    );
    if (payloads == null) {
      return const <RawSms>[];
    }

    return payloads.map(decodeRawSmsPayload).toList(growable: false);
  }
}

/// Injectable inbox reader for production backfill and fake-reader tests.
final smsInboxReaderProvider = Provider<SmsInboxReader>((ref) {
  return const PlatformSmsInboxReader();
});

/// Persisted record of whether the one-time backfill has already run.
///
/// Backed natively so it survives reinstalls-in-place and cold starts; the
/// interface lets tests drive the run-once gate without a device.
abstract interface class BackfillMarker {
  /// True once the historical backfill has completed at least once.
  Future<bool> isComplete();

  /// Records that the historical backfill has completed.
  Future<void> markComplete();
}

/// Method-channel implementation backed by Android shared preferences.
class PlatformBackfillMarker implements BackfillMarker {
  const PlatformBackfillMarker({
    MethodChannel channel = _defaultChannel,
  }) : _channel = channel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'com.paisatrack/sms_backfill',
  );

  final MethodChannel _channel;

  @override
  Future<bool> isComplete() async {
    return await _channel.invokeMethod<bool>('isBackfillComplete') ?? false;
  }

  @override
  Future<void> markComplete() async {
    await _channel.invokeMethod<void>('markBackfillComplete');
  }
}

/// Injectable backfill marker for production and fake-marker tests.
final backfillMarkerProvider = Provider<BackfillMarker>((ref) {
  return const PlatformBackfillMarker();
});

/// Backfills historical inbox SMS through the ingest pipeline in chunks.
///
/// Dedup and re-run idempotency are inherited from [SmsIngestor.ingest], which
/// upserts on the deterministic SMS id, so a message already captured live or
/// by a prior backfill is updated in place rather than duplicated.
class SmsBackfiller {
  SmsBackfiller({
    required SmsIngestor ingestor,
    required SmsInboxReader reader,
    int months = AppConstants.smsBackfillMonths,
    int chunkSize = AppConstants.smsBackfillChunkSize,
  })  : _ingestor = ingestor,
        _reader = reader,
        _months = months,
        _chunkSize = chunkSize;

  final SmsIngestor _ingestor;
  final SmsInboxReader _reader;
  final int _months;
  final int _chunkSize;

  /// Reads the last [_months] of inbox history relative to [now] and ingests it
  /// in chunks, yielding between chunks so the UI thread is never blocked.
  ///
  /// Returns the number of messages processed. Per-message failures are
  /// absorbed (no raw content is logged) so one bad row cannot abort the run.
  Future<int> run({required DateTime now}) async {
    final since = DateTime(now.year, now.month - _months, now.day);
    final messages = await _reader.readSince(since);

    var processed = 0;
    for (var start = 0; start < messages.length; start += _chunkSize) {
      final end =
          (start + _chunkSize < messages.length) ? start + _chunkSize : messages.length;
      for (final sms in messages.sublist(start, end)) {
        try {
          await _ingestor.ingest(sms);
        } catch (_) {
          // Intentionally swallowed: no raw SMS content is logged on this path.
        }
        processed++;
      }
      // Hand control back to the event loop between chunks.
      await Future<void>.delayed(Duration.zero);
    }
    return processed;
  }
}

/// Runs the historical backfill exactly once, on the first permission grant
/// while the database is ready.
///
/// A persisted [BackfillMarker] guards the run so later cold starts never
/// re-scan the inbox — re-scanning would duplicate messages already captured
/// live under a different id. Cross-source semantic duplicates (a bank SMS and
/// its wallet echo) are suppressed later by T-025.
final smsBackfillProvider = FutureProvider<int>((ref) async {
  final permission = ref.watch(smsPermissionControllerProvider).valueOrNull;
  final database = ref.watch(appDatabaseProvider).valueOrNull;
  if (permission != SmsPermissionStatus.granted || database == null) {
    return 0;
  }

  final marker = ref.read(backfillMarkerProvider);
  if (await marker.isComplete()) {
    return 0;
  }

  final parser = ref.read(parserCascadeProvider);
  final reader = ref.read(smsInboxReaderProvider);
  final ingestor = SmsIngestor(database: database, parser: parser);
  final backfiller = SmsBackfiller(ingestor: ingestor, reader: reader);
  final processed = await backfiller.run(now: DateTime.now());
  await marker.markComplete();
  return processed;
});
