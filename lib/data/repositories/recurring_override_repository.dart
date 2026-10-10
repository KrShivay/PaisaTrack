import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../intelligence/recurring_detector.dart';
import '../db/database.dart';
import '../db/database_provider.dart';
import '../models/source_currency.dart';

/// User intent for whether a transaction belongs to a recurring series.
enum RecurringOverride { automatic, recurring, notRecurring }

/// Wire value stored in `transactions.recurring_override`.
String? recurringOverrideToWire(RecurringOverride v) => switch (v) {
      RecurringOverride.automatic => null,
      RecurringOverride.recurring => 'recurring',
      RecurringOverride.notRecurring => 'not_recurring',
    };

/// Unknown or null wire values fall back to [RecurringOverride.automatic].
RecurringOverride recurringOverrideFromWire(String? v) => switch (v) {
      'recurring' => RecurringOverride.recurring,
      'not_recurring' => RecurringOverride.notRecurring,
      _ => RecurringOverride.automatic,
    };

class RecurringOverrideRepository {
  RecurringOverrideRepository(
    AppDatabase db, {
    DateTime Function() clock = DateTime.now,
  })  : _db = db,
        _clock = clock;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Updates only `recurring_override` and `updated_at`, then rebuilds the
  /// shared recurring projection (ADR 0031) so the Recurring screen and
  /// dashboard commitments reflect the change. Series status memory is
  /// preserved by [rebuildRecurringProjection].
  Future<void> setOverride(
    String transactionId,
    RecurringOverride value,
  ) async {
    final updated = await (_db.update(_db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(
      TransactionsCompanion(
        recurringOverride: Value(recurringOverrideToWire(value)),
        updatedAt: Value(_clock().toUtc()),
      ),
    );
    if (updated == 0) return;
    await rebuildRecurringProjection(_db, today: _clock());
  }

  Future<RecurringOverride> overrideFor(String transactionId) async {
    final row = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
    return recurringOverrideFromWire(row?.recurringOverride);
  }

  Stream<RecurringOverride> watchOverride(String transactionId) {
    return (_db.select(_db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .watchSingleOrNull()
        .map((row) => recurringOverrideFromWire(row?.recurringOverride));
  }

  /// Whether a live (not inactive/cancelled) detected series exists for the
  /// transaction's merchant, direction and currency bucket.
  Future<bool> isDetectedRecurring(String transactionId) async {
    final txn = await (_db.select(_db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
    if (txn == null) return false;
    final merchantId = recurringSeriesMerchantId(txn);
    if (merchantId == null) return false;
    final bucket =
        SourceCurrency(code: txn.currencyCode, symbol: txn.currencySymbol)
            .bucketKey;
    final series = await (_db.select(_db.recurringSeries)
          ..where((s) => s.merchantId.equals(merchantId)))
        .get();
    return series.any(
      (s) =>
          s.status != 'inactive' &&
          s.status != 'cancelled' &&
          (s.kind == 'income') == (txn.direction == 'credit') &&
          SourceCurrency(code: s.currencyCode, symbol: s.currencySymbol)
                  .bucketKey ==
              bucket,
    );
  }
}

final recurringOverrideRepositoryProvider =
    FutureProvider<RecurringOverrideRepository>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  return RecurringOverrideRepository(database);
});

final transactionRecurringOverrideProvider =
    StreamProvider.family<RecurringOverride, String>((ref, transactionId) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) =>
        RecurringOverrideRepository(database).watchOverride(transactionId),
    loading: () => const Stream<RecurringOverride>.empty(),
    error: (error, stackTrace) =>
        Stream<RecurringOverride>.error(error, stackTrace),
  );
});

/// Whether the detector currently treats the transaction as part of an active
/// recurring series.
final transactionDetectedRecurringProvider =
    FutureProvider.family<bool, String>((ref, transactionId) async {
  final database = await ref.watch(appDatabaseProvider.future);
  // Re-evaluate when the projection changes.
  ref.watch(_recurringSeriesTickProvider);
  return RecurringOverrideRepository(database)
      .isDetectedRecurring(transactionId);
});

final _recurringSeriesTickProvider = StreamProvider<int>((ref) {
  final databaseAsync = ref.watch(appDatabaseProvider);
  return databaseAsync.when(
    data: (database) => database
        .select(database.recurringSeries)
        .watch()
        .map((rows) => rows.length),
    loading: () => const Stream<int>.empty(),
    error: (e, s) => Stream<int>.error(e, s),
  );
});
