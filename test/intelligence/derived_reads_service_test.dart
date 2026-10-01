import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/data/repositories/recurring_repository.dart';
import 'package:paisatrack/intelligence/derived_reads_service.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 7, 10, 12);

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> category(String id) => database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: id,
          name: id,
          icon: 'category',
          isSpending: true,
          sortOrder: 1,
          isUserCreated: false,
        ),
      );

  Future<void> txn(
    String id,
    DateTime date,
    double amount,
    String categoryId, {
    String? merchantId,
    DateTime? updatedAt,
  }) =>
      database.into(database.transactions).insert(
            TransactionsCompanion.insert(
              id: id,
              ts: date.millisecondsSinceEpoch,
              amount: amount,
              currencyCode: const Value('INR'),
              currencySymbol: const Value('₹'),
              direction: 'debit',
              channel: 'test',
              categoryId: Value(categoryId),
              merchantId: Value(merchantId),
              parseSource: 'test',
              confidenceJson: '{}',
              status: 'confirmed',
              createdAt: date,
              updatedAt: updatedAt ?? date,
            ),
          );

  DerivedReadsService service({
    Duration debounce = Duration.zero,
    bool listenForChanges = false,
    Future<void> Function(DateTime today)? pipeline,
    void Function(Object, StackTrace)? onError,
  }) =>
      DerivedReadsService(
        database,
        clock: () => now,
        calendar: const FinancialCalendar.fixed(Duration.zero),
        debounceDuration: debounce,
        listenForChanges: listenForChanges,
        pipeline: pipeline,
        onError: onError,
      );

  test('recategorization recomputes category_delta and freshness stamp',
      () async {
    await category('food');
    await category('other');
    await txn('previous', DateTime.utc(2026, 6, 10), 100, 'food');
    await txn('current-food', DateTime.utc(2026, 7, 2), 150, 'food');
    await txn('current-other', DateTime.utc(2026, 7, 3), 50, 'other');
    final derived = service(
      debounce: const Duration(milliseconds: 20),
      listenForChanges: true,
    );
    addTearDown(derived.dispose);

    await derived.rebuildAll(today: now);
    var insight = (await (database.select(database.insights)
          ..where(
            (row) => row.id.equals('category_delta:2026-07:food:code:INR'),
          ))
        .getSingle());
    expect(
      (jsonDecode(insight.payloadJson)
          as Map<String, Object?>)['current_total'],
      150,
    );

    final recomputed = Completer<void>();
    final stampUpdates = database
        .tableUpdates(TableUpdateQuery.onAllTables([database.modelMeta]))
        .listen((_) async {
      final row = await (database.select(database.modelMeta)
            ..where((meta) => meta.key.equals(derivedReadsComputedAtKey)))
          .getSingleOrNull();
      if (!recomputed.isCompleted &&
          row != null &&
          (jsonDecode(row.value) as Map<String, Object?>)['fresh'] == true) {
        recomputed.complete();
      }
    });
    addTearDown(stampUpdates.cancel);
    await (database.update(database.transactions)
          ..where((row) => row.id.equals('current-other')))
        .write(
      TransactionsCompanion(
        categoryId: const Value('food'),
        updatedAt: Value(now),
      ),
    );
    await recomputed.future.timeout(const Duration(seconds: 2));
    insight = await (database.select(database.insights)
          ..where(
            (row) => row.id.equals('category_delta:2026-07:food:code:INR'),
          ))
        .getSingle();
    expect(
      (jsonDecode(insight.payloadJson)
          as Map<String, Object?>)['current_total'],
      200,
    );
    final stamp = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(derivedReadsComputedAtKey)))
        .getSingle();
    expect(jsonDecode(stamp.value), {
      'fresh': true,
      'computed_at': now.toIso8601String(),
      'max_transaction_updated_at': now.toIso8601String(),
      'transaction_count': 3,
    });
  });

  test('manual insert refreshes deterministic insight rows', () async {
    await category('fees_charges');
    await txn('previous-fee', DateTime.utc(2026, 6, 10), 20, 'fees_charges');
    final derived = service(
      debounce: const Duration(milliseconds: 20),
      listenForChanges: true,
    );
    addTearDown(derived.dispose);
    await derived.rebuildAll(today: now);
    expect(
      (await database.select(database.insights).get())
          .where((row) => row.kind == 'fees_total'),
      isEmpty,
    );

    final recomputed = Completer<void>();
    final stampUpdates = database
        .tableUpdates(TableUpdateQuery.onAllTables([database.modelMeta]))
        .listen((_) async {
      final row = await (database.select(database.modelMeta)
            ..where((meta) => meta.key.equals(derivedReadsComputedAtKey)))
          .getSingleOrNull();
      if (!recomputed.isCompleted &&
          row != null &&
          (jsonDecode(row.value) as Map<String, Object?>)['fresh'] == true) {
        recomputed.complete();
      }
    });
    addTearDown(stampUpdates.cancel);
    await txn('manual-fee', DateTime.utc(2026, 7, 10), 600, 'fees_charges');
    await recomputed.future.timeout(const Duration(seconds: 2));

    final fee = (await database.select(database.insights).get())
        .singleWhere((row) => row.kind == 'fees_total');
    expect(
      (jsonDecode(fee.payloadJson) as Map<String, Object?>)['total'],
      600,
    );
  });

  test('recurring rebuild preserves series id and user status', () async {
    await category('food');
    await database.into(database.merchants).insert(
          MerchantsCompanion.insert(
            id: 'merchant',
            canonicalName: 'Merchant',
            firstSeen: DateTime.utc(2026, 1),
            lastSeen: now,
          ),
        );
    for (var month = 1; month <= 3; month++) {
      await txn(
        'recurring-$month',
        DateTime.utc(2026, month, 1),
        649,
        'food',
        merchantId: 'merchant',
      );
    }
    final derived = service();
    addTearDown(derived.dispose);
    await derived.rebuildRecurring(today: now);
    final original =
        (await database.select(database.recurringSeries).getSingle());
    await RecurringRepository(database).setStatus(
      seriesId: original.id,
      status: 'paused',
    );
    for (var month = 4; month <= 6; month++) {
      await txn(
        'recurring-$month',
        DateTime.utc(2026, month, 1),
        799,
        'food',
        merchantId: 'merchant',
      );
    }

    await derived.rebuildRecurring(today: now);
    final rebuilt = await (database.select(database.recurringSeries)
          ..where((row) => row.id.equals(original.id)))
        .getSingle();
    final shifted = (await database.select(database.recurringSeries).get())
        .singleWhere((row) => row.expectedAmount == 799);
    expect(rebuilt.id, original.id);
    expect(rebuilt.status, 'paused');
    expect(shifted.status, 'missed');
  });

  test('twenty writes coalesce into at most two pipeline runs', () async {
    await category('other');
    final derived = service(
      debounce: const Duration(milliseconds: 40),
      listenForChanges: true,
    );
    addTearDown(derived.dispose);
    var stampUpdates = 0;
    final updates = database
        .tableUpdates(TableUpdateQuery.onAllTables([database.modelMeta]))
        .listen((_) => stampUpdates++);
    addTearDown(updates.cancel);

    for (var index = 0; index < 20; index++) {
      await txn(
        'burst-$index',
        DateTime.utc(2026, 7, 1).add(Duration(minutes: index)),
        10,
        'other',
        updatedAt: now,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(stampUpdates, lessThanOrEqualTo(2));
    expect(stampUpdates, greaterThanOrEqualTo(1));
  });

  test('startup schedules a rebuild when the freshness stamp is missing',
      () async {
    final ran = Completer<void>();
    final derived = service(
      pipeline: (_) async {
        if (!ran.isCompleted) ran.complete();
      },
    );
    addTearDown(derived.dispose);

    await derived.startupReconciliation;
    await ran.future.timeout(const Duration(seconds: 1));
  });

  test('startup rebuilds when the persisted freshness stamp is stale',
      () async {
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: derivedReadsComputedAtKey,
            value: jsonEncode({
              'fresh': true,
              'max_transaction_updated_at': '2026-01-01T00:00:00.000Z',
              'transaction_count': 0,
            }),
          ),
        );
    final ran = Completer<void>();
    final derived = service(
      pipeline: (_) async {
        if (!ran.isCompleted) ran.complete();
      },
    );
    addTearDown(derived.dispose);

    await derived.startupReconciliation;
    await ran.future.timeout(const Duration(seconds: 1));
  });

  test('pipeline errors are logged and a later invalidate can run', () async {
    var attempts = 0;
    final errors = <Object>[];
    final derived = service(
      debounce: const Duration(hours: 1),
      pipeline: (_) async {
        attempts++;
        if (attempts == 1) throw StateError('pipeline failed');
      },
      onError: (error, _) => errors.add(error),
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    await expectLater(derived.invalidate(immediate: true), throwsStateError);
    final afterFailure = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(derivedReadsComputedAtKey)))
        .getSingle();
    expect((jsonDecode(afterFailure.value) as Map)['fresh'], isFalse);
    await derived.invalidate(immediate: true);
    expect(attempts, 2);
    expect(errors, hasLength(1));
  });

  test('writes during a run coalesce into one debounced trailing run',
      () async {
    final starts = <Completer<void>>[];
    final releases = <Completer<void>>[];
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var firstCompleted = false;
    final derived = service(
      debounce: const Duration(milliseconds: 25),
      pipeline: (_) async {
        final started = Completer<void>();
        final release = Completer<void>();
        starts.add(started);
        releases.add(release);
        started.complete();
        if (!firstStarted.isCompleted) firstStarted.complete();
        if (starts.length == 2) secondStarted.complete();
        if (starts.length <= 2) await release.future;
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    final first = derived.invalidate(immediate: true);
    unawaited(first.then((_) => firstCompleted = true));
    await firstStarted.future.timeout(const Duration(seconds: 1));
    await derived.invalidate();
    await derived.invalidate();
    releases.first.complete();
    await secondStarted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final firstCompletedBeforeTrailingFinished = firstCompleted;
    releases[1].complete();
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(firstCompletedBeforeTrailingFinished, isTrue);
    expect(starts, hasLength(2));
  });

  test('a transaction update during a run leaves its stamp stale', () async {
    await category('food');
    await txn('before', now, 100, 'food');
    final entered = Completer<void>();
    final release = Completer<void>();
    final derived = service(
      pipeline: (_) async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    final run = derived.invalidate(immediate: true);
    await entered.future;
    await txn('during', now.add(const Duration(minutes: 1)), 200, 'food');
    await derived.invalidate();
    release.complete();
    await run;
    final stamp = await (database.select(database.modelMeta)
          ..where((row) => row.key.equals(derivedReadsComputedAtKey)))
        .getSingle();
    expect((jsonDecode(stamp.value) as Map)['fresh'], isFalse);
  });

  test('immediate invalidation while running awaits the next run', () async {
    final starts = <Completer<void>>[];
    final releases = <Completer<void>>[];
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    var firstCompleted = false;
    final derived = service(
      pipeline: (_) async {
        final started = Completer<void>()..complete();
        final release = Completer<void>();
        starts.add(started);
        releases.add(release);
        if (starts.length == 1) firstStarted.complete();
        if (starts.length == 2) secondStarted.complete();
        await release.future;
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    final first = derived.invalidate(immediate: true);
    unawaited(first.then((_) => firstCompleted = true));
    await firstStarted.future.timeout(const Duration(seconds: 1));
    var secondCompleted = false;
    final second = derived.invalidate(immediate: true).then((_) {
      secondCompleted = true;
    });
    releases.first.complete();
    await secondStarted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final firstCompletedBeforeNextFinished = firstCompleted;
    final secondCompletedBeforeNextFinished = secondCompleted;
    releases[1].complete();
    await first;
    await second;
    expect(starts, hasLength(2));
    expect(firstCompletedBeforeNextFinished, isTrue);
    expect(secondCompletedBeforeNextFinished, isFalse);
    expect(secondCompleted, isTrue);
  });

  test('trailing immediate waiter survives a run ending while suspended',
      () async {
    final releases = <Completer<void>>[];
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final derived = service(
      pipeline: (_) async {
        final release = Completer<void>();
        releases.add(release);
        if (releases.length == 1) firstStarted.complete();
        if (releases.length == 2) secondStarted.complete();
        await release.future;
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    final first = derived.invalidate(immediate: true);
    await firstStarted.future;
    final trailing = derived.invalidate(immediate: true);
    final suspendedAction = Completer<void>();
    final suspension = derived.withInvalidationSuspended(
      () => suspendedAction.future,
    );
    releases.first.complete();
    await Future<void>.delayed(Duration.zero);
    suspendedAction.complete();
    await suspension;
    var resumed = true;
    try {
      await secondStarted.future.timeout(const Duration(seconds: 1));
    } on TimeoutException {
      resumed = false;
    }
    if (releases.length > 1) releases[1].complete();
    await derived.dispose();
    await first;
    await trailing;
    expect(resumed, isTrue);
    expect(releases, hasLength(2));
  });

  test('immediate invalidation while suspended awaits the resumed rebuild',
      () async {
    final releases = <Completer<void>>[];
    final started = <Completer<void>>[];
    final derived = service(
      pipeline: (_) async {
        final release = Completer<void>();
        releases.add(release);
        started.add(Completer<void>()..complete());
        await release.future;
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    final suspensionAction = Completer<void>();
    final suspension = derived.withInvalidationSuspended(
      () => suspensionAction.future,
    );
    var rebuildCompleted = false;
    final rebuild = derived.invalidate(immediate: true).then((_) {
      rebuildCompleted = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(rebuildCompleted, isFalse);
    suspensionAction.complete();
    await suspension;
    await started.first.future.timeout(const Duration(seconds: 1));
    final completedBeforePipeline = rebuildCompleted;
    releases.first.complete();
    await rebuild;
    expect(completedBeforePipeline, isFalse);
    expect(rebuildCompleted, isTrue);
  });

  test('suspension resumes after its action throws', () async {
    final ran = Completer<void>();
    final derived = service(
      pipeline: (_) async {
        if (!ran.isCompleted) ran.complete();
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    await expectLater(
      derived.withInvalidationSuspended(() async {
        await derived.invalidate(immediate: true);
        throw StateError('catch-up failed');
      }),
      throwsStateError,
    );
    await ran.future.timeout(const Duration(seconds: 1));
    await derived.invalidate(immediate: true);
  });

  test('bulk changes resume with one derived rebuild', () async {
    await category('food');
    await database.into(database.modelMeta).insert(
          ModelMetaCompanion.insert(
            key: derivedReadsComputedAtKey,
            value: jsonEncode({
              'fresh': true,
              'max_transaction_updated_at': null,
              'transaction_count': 0,
            }),
          ),
        );
    var runs = 0;
    final derived = service(
      debounce: const Duration(milliseconds: 15),
      listenForChanges: true,
      pipeline: (_) async {
        runs++;
      },
    );
    addTearDown(derived.dispose);
    await derived.startupReconciliation;

    await derived.withInvalidationSuspended(() async {
      await txn('bulk-1', now, 10, 'food');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await txn('bulk-2', now.add(const Duration(minutes: 1)), 20, 'food');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await txn('bulk-3', now.add(const Duration(minutes: 2)), 30, 'food');
    });
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(runs, 1);
  });
}
