import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/clock.dart';
import '../core/financial_calendar.dart';
import '../data/db/database.dart';
import '../data/db/database_provider.dart';
import '../data/repositories/recurring_status_memory.dart';
import 'anomaly_detector.dart';
import 'burn_rate_forecaster.dart';
import 'insights_engine.dart';
import 'models/embedder.dart';
import 'recurring_detector.dart';

const derivedReadsComputedAtKey = 'derived_reads_computed_at_v1';
const derivedReadsDebounceDuration = Duration(milliseconds: 1500);

/// Coordinates foreground freshness and the shared deterministic pipeline.
class DerivedReadsService {
  DerivedReadsService(
    this.database, {
    DateTime Function()? clock,
    this.recurringEmbedder = const NoopEmbedder(),
    this.debounceDuration = derivedReadsDebounceDuration,
    this.calendar,
    bool listenForChanges = true,
    Future<void> Function(DateTime today)? pipeline,
    void Function(Object error, StackTrace stackTrace)? onError,
  }) : _clock = clock ?? DateTime.now {
    _pipeline = pipeline;
    _onError = onError ??
        (error, stackTrace) => developer.log(
              'Derived reads rebuild failed',
              name: 'paisa.intelligence',
              error: error,
              stackTrace: stackTrace,
            );
    if (listenForChanges) {
      _updates = database
          .tableUpdates(
            TableUpdateQuery.onAllTables([
              database.transactions,
              database.categories,
              database.paymentSources,
            ]),
          )
          .listen((_) => unawaited(invalidate()));
    }
    startupReconciliation = _reconcileAtStartup();
    unawaited(startupReconciliation);
  }

  final AppDatabase database;
  final DateTime Function() _clock;
  final Embedder recurringEmbedder;
  final Duration debounceDuration;
  final FinancialCalendar? calendar;
  late final Future<void> Function(DateTime today)? _pipeline;
  late final void Function(Object, StackTrace) _onError;
  late final Future<void> startupReconciliation;
  StreamSubscription<Set<TableUpdate>>? _updates;
  Timer? _timer;
  Future<void>? _running;
  bool _trailing = false;
  bool _disposed = false;
  bool _freshnessMarkedStale = false;
  Future<void>? _staleWrite;
  bool _suspendedChanged = false;
  int _generation = 0;
  int _suspendDepth = 0;
  final List<Completer<void>> _immediateWaiters = [];

  /// Schedules a debounced rebuild, or awaits it when [immediate] is true.
  Future<void> invalidate({bool immediate = false}) {
    if (_disposed) return Future<void>.value();
    _generation++;
    if (_suspendDepth > 0) {
      _suspendedChanged = true;
      _trailing = true;
      if (!immediate) return Future<void>.value();
      final waiter = Completer<void>();
      _immediateWaiters.add(waiter);
      return waiter.future;
    }
    _timer?.cancel();
    final staleWrite = _markFreshnessStale();
    if (_suspendDepth > 0) return staleWrite;
    final running = _running;
    if (running != null) {
      _trailing = true;
      if (!immediate) return staleWrite;
      _runImmediatelyAfterCurrent = true;
      final waiter = Completer<void>();
      _immediateWaiters.add(waiter);
      return staleWrite.then((_) => waiter.future);
    }
    if (!immediate) {
      _scheduleRun(debounceDuration);
      return staleWrite;
    }
    return staleWrite.then((_) => _startRun());
  }

  Future<void> rebuildAll({DateTime? today}) async {
    final runAt = (today ?? _clock()).toUtc();
    await _rebuildStages(runAt);
    await writeFreshnessStamp();
  }

  Future<void> _rebuildStages(DateTime runAt) async {
    if (_pipeline case final pipeline?) {
      await pipeline(runAt);
      return;
    }
    await rebuildRecurring(today: runAt);
    await rebuildAnomalies(today: runAt);
    await rebuildForecastAndInsights(today: runAt);
  }

  Future<void> rebuildRecurring({DateTime? today}) async {
    final statuses = await RecurringStatusMemory.read(database);
    final previous = await database.select(database.recurringSeries).get();
    final previousIds = previous.map((row) => row.id).toSet();
    for (final row in previous) {
      if (RecurringStatusMemory.isUserControlled(row.status)) {
        final key = RecurringStatusMemory.identity(row);
        statuses[key] = row.status;
        await RecurringStatusMemory.remember(database, key, row.status);
      }
    }
    final detections = await RecurringDetector(
      database,
      embedder: recurringEmbedder,
    ).run(today: today);
    final detectedIds = detections.map((row) => row.id).toSet();
    await database.transaction(() async {
      final current = await database.select(database.recurringSeries).get();
      for (final row in current) {
        final status = previousIds.contains(row.id)
            ? null
            : statuses[RecurringStatusMemory.identity(row)];
        if (status != null && row.status != status) {
          await (database.update(database.recurringSeries)
                ..where((item) => item.id.equals(row.id)))
              .write(RecurringSeriesCompanion(status: Value(status)));
        }
        if (!detectedIds.contains(row.id)) {
          await (database.delete(database.recurringSeries)
                ..where((item) => item.id.equals(row.id)))
              .go();
        }
      }
    });
  }

  Future<void> rebuildAnomalies({DateTime? today}) async {
    await AnomalyDetector(database, calendar: calendar)
        .run(today: today ?? _clock());
  }

  Future<void> rebuildForecastAndInsights({DateTime? today}) async {
    final runAt = today ?? _clock();
    await BurnRateForecaster(database, calendar: calendar).run(today: runAt);
    await InsightsEngine(database, calendar: calendar).run(today: runAt);
  }

  Future<void> writeFreshnessStamp({
    int? generationAtStart,
    TransactionFreshnessSnapshot? snapshotAtStart,
  }) async {
    final snapshot = await readTransactionFreshnessSnapshot(database);
    final fresh = (generationAtStart == null ||
            generationAtStart == _generation && !_disposed) &&
        (snapshotAtStart == null || snapshot == snapshotAtStart);
    await database.into(database.modelMeta).insertOnConflictUpdate(
          ModelMetaCompanion.insert(
            key: derivedReadsComputedAtKey,
            value: jsonEncode({
              'fresh': fresh,
              'computed_at': _clock().toUtc().toIso8601String(),
              'max_transaction_updated_at': snapshot.maxUpdatedAt,
              'transaction_count': snapshot.count,
            }),
          ),
        );
    _freshnessMarkedStale = !fresh;
    if (fresh) _staleWrite = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _updates?.cancel();
    try {
      await _running;
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
    for (final waiter in _immediateWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _immediateWaiters.clear();
  }

  bool _runImmediatelyAfterCurrent = false;

  Future<void> _startRun() {
    if (_disposed) return Future<void>.value();
    final running = _running;
    if (running != null) return running;
    _timer?.cancel();
    _timer = null;
    _trailing = false;
    final generationAtStart = _generation;
    final completer = Completer<void>();
    _running = completer.future;
    final waiters = List<Completer<void>>.of(_immediateWaiters);
    _immediateWaiters.clear();
    () async {
      try {
        final snapshotAtStart =
            await readTransactionFreshnessSnapshot(database);
        await _rebuildStages(_clock().toUtc());
        await writeFreshnessStamp(
          generationAtStart: generationAtStart,
          snapshotAtStart: snapshotAtStart,
        );
        completer.complete();
        for (final waiter in waiters) {
          if (!waiter.isCompleted) waiter.complete();
        }
      } on Object catch (error, stackTrace) {
        _onError(error, stackTrace);
        completer.completeError(error, stackTrace);
        for (final waiter in waiters) {
          if (!waiter.isCompleted) waiter.completeError(error, stackTrace);
        }
      } finally {
        _running = null;
        if (_trailing && !_disposed && _suspendDepth == 0) {
          final delay =
              _runImmediatelyAfterCurrent ? Duration.zero : debounceDuration;
          _runImmediatelyAfterCurrent = false;
          _scheduleRun(delay);
        }
      }
    }();
    return completer.future;
  }

  void _scheduleRun(Duration delay) {
    if (_disposed || _suspendDepth > 0 || _running != null) return;
    _timer?.cancel();
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(_startRun().catchError((Object _, StackTrace __) {}));
    });
  }

  Future<void> _reconcileAtStartup() async {
    try {
      final stamp = await (database.select(database.modelMeta)
            ..where((row) => row.key.equals(derivedReadsComputedAtKey)))
          .getSingleOrNull();
      var current = false;
      if (stamp != null) {
        try {
          final value = jsonDecode(stamp.value);
          if (value is Map && value['fresh'] == true) {
            final snapshot = await readTransactionFreshnessSnapshot(database);
            current =
                value['max_transaction_updated_at'] == snapshot.maxUpdatedAt &&
                    value['transaction_count'] == snapshot.count;
          }
        } on FormatException {
          current = false;
        }
      }
      if (!current) await invalidate();
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  Future<T> withInvalidationSuspended<T>(Future<T> Function() action) async {
    _suspendDepth++;
    try {
      return await action();
    } finally {
      _suspendDepth--;
      if (_suspendDepth == 0 &&
          !_disposed &&
          (_trailing || _suspendedChanged || _immediateWaiters.isNotEmpty)) {
        final immediate = _immediateWaiters.isNotEmpty;
        _suspendedChanged = false;
        if (immediate) {
          unawaited(
            invalidate(immediate: true).catchError(
              (Object _, StackTrace __) {},
            ),
          );
        } else {
          await invalidate();
        }
      }
    }
  }

  Future<void> _markFreshnessStale() {
    if (_freshnessMarkedStale) return _staleWrite ?? Future<void>.value();
    _freshnessMarkedStale = true;
    final staleWrite = () async {
      final current = await (database.select(database.modelMeta)
            ..where((row) => row.key.equals(derivedReadsComputedAtKey)))
          .getSingleOrNull();
      await database.into(database.modelMeta).insertOnConflictUpdate(
            ModelMetaCompanion.insert(
              key: derivedReadsComputedAtKey,
              value: jsonEncode({
                'fresh': false,
                'computed_at': _clock().toUtc().toIso8601String(),
                if (current != null) 'previous_stamp': current.value,
              }),
            ),
          );
    }();
    return _staleWrite =
        staleWrite.catchError((Object error, StackTrace trace) {
      _freshnessMarkedStale = false;
      _staleWrite = null;
      Error.throwWithStackTrace(error, trace);
    });
  }
}

class TransactionFreshnessSnapshot {
  const TransactionFreshnessSnapshot({this.maxUpdatedAt, required this.count});

  final String? maxUpdatedAt;
  final int count;

  @override
  bool operator ==(Object other) =>
      other is TransactionFreshnessSnapshot &&
      other.maxUpdatedAt == maxUpdatedAt &&
      other.count == count;

  @override
  int get hashCode => Object.hash(maxUpdatedAt, count);
}

Future<TransactionFreshnessSnapshot> readTransactionFreshnessSnapshot(
  AppDatabase database,
) async {
  final maxUpdatedAt = database.transactions.updatedAt.max();
  final count = database.transactions.id.count();
  final row = await (database.selectOnly(database.transactions)
        ..addColumns([maxUpdatedAt, count]))
      .getSingle();
  return TransactionFreshnessSnapshot(
    maxUpdatedAt: row.read(maxUpdatedAt)?.toUtc().toIso8601String(),
    count: row.read(count) ?? 0,
  );
}

final derivedReadsServiceProvider =
    FutureProvider<DerivedReadsService>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final clock = ref.watch(clockProvider);
  final service = DerivedReadsService(
    database,
    clock: clock,
    calendar: ref.watch(financialCalendarProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
