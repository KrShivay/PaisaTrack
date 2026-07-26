import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/db/database.dart';
import '../data/db/database_provider.dart';
import '../data/models/raw_sms.dart';
import '../enrichment/categorizer.dart';
import '../enrichment/decision_policy.dart';
import '../features/settings/app_settings.dart';
import '../intelligence/nightly_job.dart';
import '../intelligence/models/embedder.dart';
import '../intelligence/recurring_detector.dart';
import 'captured_sms_source.dart';
import 'parser_cascade.dart';
import 'permissions/sms_permission.dart';
import 'permissions/sms_permission_provider.dart';
import 'sms_import_state.dart';
import 'sms_ingestion.dart';

class SmsInboxCursor {
  const SmsInboxCursor({
    required this.beforeEpochMillis,
    required this.beforeId,
  });

  final int beforeEpochMillis;
  final int beforeId;

  @override
  bool operator ==(Object other) =>
      other is SmsInboxCursor &&
      other.beforeEpochMillis == beforeEpochMillis &&
      other.beforeId == beforeId;

  @override
  int get hashCode => Object.hash(beforeEpochMillis, beforeId);
}

class SmsInboxPage {
  const SmsInboxPage({required this.messages, this.nextCursor});

  final List<RawSms> messages;
  final SmsInboxCursor? nextCursor;
}

/// Reads filter-approved SMS in bounded pages until the inbox is exhausted.
abstract interface class SmsInboxReader {
  Future<SmsInboxPage> readPage({
    SmsInboxCursor? before,
    required int limit,
  });
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
  Future<SmsInboxPage> readPage({
    SmsInboxCursor? before,
    required int limit,
  }) async {
    final response = await _channel.invokeMethod<Object?>(
      'readInboxPage',
      <String, Object?>{
        if (before != null) ...{
          'beforeEpochMillis': before.beforeEpochMillis,
          'beforeId': before.beforeId,
        },
        'limit': limit,
      },
    );
    if (response is! Map<Object?, Object?>) {
      throw const FormatException('Invalid SMS inbox page payload');
    }
    final payloads = response['messages'];
    if (payloads is! List<Object?>) {
      throw const FormatException('Invalid SMS inbox messages payload');
    }
    final hasMore = response['hasMore'] == true;
    final nextEpoch = response['nextBeforeEpochMillis'];
    final nextId = response['nextBeforeId'];
    if (hasMore && (nextEpoch is! int || nextId is! int)) {
      throw const FormatException('Invalid SMS inbox cursor payload');
    }

    return SmsInboxPage(
      messages: payloads.map(decodeRawSmsPayload).toList(growable: false),
      nextCursor: hasMore
          ? SmsInboxCursor(
              beforeEpochMillis: nextEpoch as int,
              beforeId: nextId as int,
            )
          : null,
    );
  }
}

/// Injectable inbox reader for production backfill and fake-reader tests.
final smsInboxReaderProvider = Provider<SmsInboxReader>((ref) {
  return const PlatformSmsInboxReader();
});

class SmsImportProgress {
  const SmsImportProgress({required this.processed, required this.failed});

  final int processed;
  final int failed;
}

class SmsImportResult extends SmsImportProgress {
  const SmsImportResult({
    required super.processed,
    required super.failed,
    this.skipped = false,
  });

  final bool skipped;
}

/// Backfills historical inbox SMS through the ingest pipeline in chunks.
///
/// Dedup and re-run idempotency are inherited from [SmsIngestor.ingest], which
/// upserts on the deterministic SMS id, so a message already captured live or
/// by a prior backfill is updated in place rather than duplicated.
class SmsBackfiller {
  SmsBackfiller({
    required SmsIngestor ingestor,
    required SmsInboxReader reader,
    int pageSize = AppConstants.smsHistoryImportPageSize,
  })  : _ingestor = ingestor,
        _reader = reader,
        _pageSize = pageSize;

  final SmsIngestor _ingestor;
  final SmsInboxReader _reader;
  final int _pageSize;

  /// Scans the complete inbox, newest first, in bounded pages.
  Future<SmsImportResult> run({
    SmsInboxCursor? initialCursor,
    FutureOr<void> Function(SmsInboxCursor cursor)? onPageCompleted,
    void Function(SmsImportProgress progress)? onProgress,
  }) async {
    var processed = 0;
    var failed = 0;
    var cursor = initialCursor;
    do {
      final page = await _reader.readPage(before: cursor, limit: _pageSize);
      final batch = await _ingestor.ingestBatch(page.messages);
      failed += batch.failed;
      processed += page.messages.length;
      onProgress?.call(SmsImportProgress(processed: processed, failed: failed));
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw StateError('SMS inbox pagination did not advance');
      }
      if (page.nextCursor != null) {
        await onPageCompleted?.call(page.nextCursor!);
      }
      cursor = page.nextCursor;
      await Future<void>.delayed(Duration.zero);
    } while (cursor != null);
    return SmsImportResult(processed: processed, failed: failed);
  }
}

class SmsIncrementalCatchUp {
  SmsIncrementalCatchUp({
    required AppDatabase database,
    required SmsIngestor ingestor,
    required SmsInboxReader reader,
    required BackfillMarker marker,
    int pageSize = AppConstants.smsHistoryImportPageSize,
  })  : _database = database,
        _ingestor = ingestor,
        _reader = reader,
        _marker = marker,
        _pageSize = pageSize;

  final AppDatabase _database;
  final SmsIngestor _ingestor;
  final SmsInboxReader _reader;
  final BackfillMarker _marker;
  final int _pageSize;
  Future<SmsImportResult>? _active;

  Future<SmsImportResult> run() {
    return _active ??= _run().whenComplete(() => _active = null);
  }

  Future<SmsImportResult> _run() async {
    if (await _marker.completedVersion() < smsHistoryImportVersion) {
      return const SmsImportResult(processed: 0, failed: 0, skipped: true);
    }
    var cursor = null as SmsInboxCursor?;
    var processed = 0;
    var failed = 0;
    var recoveryPagesLeft = 1;
    var foundKnownBoundary = false;
    do {
      final page = await _reader.readPage(before: cursor, limit: _pageSize);
      final pageIds = page.messages.map((sms) => sms.id).toList();
      final knownIds = <String>{};
      if (pageIds.isNotEmpty) {
        final rawId = _database.rawSms.id;
        final rawRows = await (_database.selectOnly(_database.rawSms)
              ..addColumns([rawId])
              ..where(rawId.isIn(pageIds)))
            .get();
        knownIds.addAll(rawRows.map((row) => row.read(rawId)!));

        final transactionSmsId = _database.transactions.smsId;
        final transactionRows = await (_database.selectOnly(
          _database.transactions,
        )
              ..addColumns([transactionSmsId])
              ..where(transactionSmsId.isIn(pageIds)))
            .get();
        knownIds.addAll(
          transactionRows.map((row) => row.read(transactionSmsId)!),
        );
      }
      final pending = <RawSms>[];
      for (final sms in page.messages) {
        if (knownIds.contains(sms.id)) {
          foundKnownBoundary = true;
          continue;
        }
        pending.add(sms);
      }
      final batch = await _ingestor.ingestBatch(pending);
      failed += batch.failed;
      processed += pending.length;
      if (page.nextCursor != null && page.nextCursor == cursor) {
        throw StateError('SMS inbox pagination did not advance');
      }
      // Finish the boundary page and one older page. This bounded overlap
      // recovers an isolated live-ingest failure hidden behind a newer known
      // SMS without turning every resume into a full-history rescan.
      if (foundKnownBoundary) {
        if (recoveryPagesLeft == 0 || page.nextCursor == null) {
          return SmsImportResult(processed: processed, failed: failed);
        }
        recoveryPagesLeft--;
      }
      cursor = page.nextCursor;
    } while (cursor != null);
    return SmsImportResult(processed: processed, failed: failed);
  }
}

abstract interface class SmsHistoryImportRunner {
  Future<SmsImportResult> run({
    bool force = false,
    void Function(SmsImportProgress progress)? onProgress,
  });
}

class SmsHistoryImporter implements SmsHistoryImportRunner {
  SmsHistoryImporter({
    required SmsBackfiller backfiller,
    required BackfillMarker marker,
  })  : _backfiller = backfiller,
        _marker = marker;

  final SmsBackfiller _backfiller;
  final BackfillMarker _marker;
  Future<SmsImportResult>? _active;

  @override
  Future<SmsImportResult> run({
    bool force = false,
    void Function(SmsImportProgress progress)? onProgress,
  }) {
    return _active ??= _run(force: force, onProgress: onProgress).whenComplete(
      () => _active = null,
    );
  }

  Future<SmsImportResult> _run({
    required bool force,
    void Function(SmsImportProgress progress)? onProgress,
  }) async {
    if (!force && await _marker.completedVersion() >= smsHistoryImportVersion) {
      return const SmsImportResult(processed: 0, failed: 0, skipped: true);
    }
    final checkpoint = force ? null : await _marker.checkpoint();
    final result = await _backfiller.run(
      initialCursor: checkpoint == null
          ? null
          : SmsInboxCursor(
              beforeEpochMillis: checkpoint.beforeEpochMillis,
              beforeId: checkpoint.beforeId,
            ),
      onPageCompleted: force
          ? null
          : (cursor) => _marker.saveCheckpoint(
                SmsImportCheckpoint(
                  beforeEpochMillis: cursor.beforeEpochMillis,
                  beforeId: cursor.beforeId,
                ),
              ),
      onProgress: onProgress,
    );
    // Reaching the end proves the inbox scan completed. Individual messages
    // are isolated so a single malformed/unsupported row cannot force a full
    // re-scan on every launch; manual re-import remains available to retry.
    // Page/query failures still throw before this marker is written.
    await _marker.markCompleted(smsHistoryImportVersion);
    return result;
  }
}

final smsHistoryImportRunnerProvider =
    FutureProvider<SmsHistoryImportRunner>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final knownTransactionIds =
      (await database.select(database.transactions).get())
          .map((row) => row.id)
          .toSet();
  // Bulk import must stay deterministic and bounded. Running a language model
  // once per historical template miss makes a large inbox take hours and pins
  // the CPU. Template + generic parsing cover the bulk path; unresolved rows
  // remain available for later parser improvements until raw-SMS retention.
  final parser = ParserCascade(
    templateMatcher: await ref.watch(templateMatcherProvider.future),
  );
  final categorizer = await ref.watch(categorizerProvider.future);
  final ingestor = SmsIngestor(
    database: database,
    parser: parser,
    categorizer: categorizer,
    fixedStatus: DecisionStatus.needsReview,
    knownTransactionIds: knownTransactionIds,
    // Avoid one embedding-model invocation per new historical merchant. Raw
    // merchant text and deterministic categorization are still imported.
    askDailyBudgetResolver: () =>
        ref.read(appSettingsControllerProvider).valueOrNull?.askDailyBudget ??
        AppConstants.askNowDailyBudget,
  );
  return SmsHistoryImporter(
    backfiller: SmsBackfiller(
      ingestor: ingestor,
      reader: ref.watch(smsInboxReaderProvider),
    ),
    marker: ref.watch(backfillMarkerProvider),
  );
});

final smsIncrementalCatchUpProvider =
    FutureProvider<SmsIncrementalCatchUp>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final parser = ParserCascade(
    templateMatcher: await ref.watch(templateMatcherProvider.future),
  );
  final categorizer = await ref.watch(categorizerProvider.future);
  return SmsIncrementalCatchUp(
    database: database,
    ingestor: SmsIngestor(
      database: database,
      parser: parser,
      categorizer: categorizer,
      fixedStatus: DecisionStatus.needsReview,
      askDailyBudgetResolver: () =>
          ref.read(appSettingsControllerProvider).valueOrNull?.askDailyBudget ??
          AppConstants.askNowDailyBudget,
    ),
    reader: ref.watch(smsInboxReaderProvider),
    marker: ref.watch(backfillMarkerProvider),
  );
});

final smsIncrementalCatchUpBootstrapProvider = Provider<void>((ref) {
  final permission = ref.watch(smsPermissionControllerProvider).valueOrNull;
  final catchUp = ref.watch(smsIncrementalCatchUpProvider).valueOrNull;
  final database = ref.watch(appDatabaseProvider).valueOrNull;
  final backfill = ref.watch(smsBackfillProvider);
  if (permission != SmsPermissionStatus.granted ||
      catchUp == null ||
      database == null ||
      backfill.isLoading) {
    return;
  }

  void runCatchUp() => unawaited(_runCatchUpSafely(catchUp, database));
  final observer = _SmsCatchUpLifecycleObserver(runCatchUp);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  runCatchUp();
});

Future<void> _runCatchUpSafely(
  SmsIncrementalCatchUp catchUp,
  AppDatabase database,
) async {
  try {
    await catchUp.run();
    await ForegroundRecurringScanner(
      database,
      embedder: const PlatformEmbedder(),
    ).runIfStale();
    await NightlyPipeline.production(database).runStages(
      only: {NightlyStage.purgeExpiredRawSms},
    );
  } catch (error, stackTrace) {
    developer.log(
      'Incremental SMS catch-up failed',
      name: 'paisatrack.sms_import',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _SmsCatchUpLifecycleObserver with WidgetsBindingObserver {
  const _SmsCatchUpLifecycleObserver(this._onResume);

  final void Function() _onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }
}

enum SmsBackfillStage { idle, running, completed, failed }

class SmsBackfillStatusState {
  const SmsBackfillStatusState({
    this.stage = SmsBackfillStage.idle,
    this.processed = 0,
    this.failed = 0,
  });

  final SmsBackfillStage stage;
  final int processed;
  final int failed;

  SmsBackfillStatusState copyWith({
    SmsBackfillStage? stage,
    int? processed,
    int? failed,
  }) {
    return SmsBackfillStatusState(
      stage: stage ?? this.stage,
      processed: processed ?? this.processed,
      failed: failed ?? this.failed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SmsBackfillStatusState &&
          runtimeType == other.runtimeType &&
          stage == other.stage &&
          processed == other.processed &&
          failed == other.failed;

  @override
  int get hashCode => Object.hash(stage, processed, failed);
}

class SmsBackfillStatusNotifier extends StateNotifier<SmsBackfillStatusState> {
  SmsBackfillStatusNotifier() : super(const SmsBackfillStatusState());

  void markRunning() {
    state = const SmsBackfillStatusState(stage: SmsBackfillStage.running);
  }

  void updateProgress({required int processed, required int failed}) {
    state = state.copyWith(
      stage: SmsBackfillStage.running,
      processed: processed,
      failed: failed,
    );
  }

  void markCompleted({required int processed, required int failed}) {
    state = state.copyWith(
      stage: SmsBackfillStage.completed,
      processed: processed,
      failed: failed,
    );
  }

  void markFailed() {
    state = state.copyWith(stage: SmsBackfillStage.failed);
  }
}

final smsBackfillStatusProvider =
    StateNotifierProvider<SmsBackfillStatusNotifier, SmsBackfillStatusState>(
  (ref) => SmsBackfillStatusNotifier(),
);

/// Runs the newest full-history import version once permission and DB are ready.
final smsBackfillProvider = FutureProvider<int>((ref) async {
  final permission = ref.watch(smsPermissionControllerProvider).valueOrNull;
  if (permission != SmsPermissionStatus.granted) return 0;
  // Keep inbox/database maintenance out of the first rendered frame. The
  // incremental path is page-bounded, so an arbitrary wall-clock delay is no
  // longer needed and would leave timers behind when widget tests dispose.
  await WidgetsBinding.instance.endOfFrame;
  final notifier = ref.read(smsBackfillStatusProvider.notifier);
  // Reset before awaiting: this provider re-runs on permission changes and
  // would otherwise render the previous run's completed count as live.
  notifier.markRunning();
  try {
    final runner = await ref.watch(smsHistoryImportRunnerProvider.future);
    final result = await runner.run(
      force: false,
      onProgress: (progress) {
        notifier.updateProgress(
          processed: progress.processed,
          failed: progress.failed,
        );
      },
    );
    notifier.markCompleted(
      processed: result.processed,
      failed: result.failed,
    );
    return result.processed;
  } catch (error, stackTrace) {
    notifier.markFailed();
    // Keep diagnostics content-free: platform/query errors are actionable,
    // while SMS sender/body data must never enter logs.
    developer.log(
      'Automatic SMS history import failed',
      name: 'paisatrack.sms_import',
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
});
