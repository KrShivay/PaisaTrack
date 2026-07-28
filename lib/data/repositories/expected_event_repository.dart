import 'package:drift/drift.dart';

import '../db/database.dart';

/// Repository for managing ExpectedEvents (T-138b).
/// Expected events capture bill-due reminders, mandates, and upcoming obligations.
/// Invariant: Expected events NEVER enter spending totals or transactions.
class ExpectedEventRepository {
  ExpectedEventRepository(this._db);

  final AppDatabase _db;

  /// Derive stable deduplication key for one obligation across multiple reminders.
  static String computeDedupKey({
    required String label,
    String? counterpartyId,
    String? cadence,
    required int amountPaise,
  }) {
    final cpty = counterpartyId ?? label.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final cad = cadence ?? 'monthly';
    // Group amount into ~100 INR buckets (10000 paise) to absorb minor fee variations
    final roughAmt = (amountPaise / 10000).round();
    return '${cpty}_${cad}_$roughAmt';
  }

  /// Ingest an expected event, deduplicating on (dedup_key, expected_date).
  Future<void> recordExpectedEvent({
    required String source,
    String? originSmsId,
    String? seriesId,
    String? counterpartyId,
    required String label,
    required int expectedAmountPaise,
    int? amountLowPaise,
    int? amountHighPaise,
    required DateTime expectedDate,
    int dateWindowDays = 3,
    String? cadence,
    required double confidence,
  }) async {
    final dedupKey = computeDedupKey(
      label: label,
      counterpartyId: counterpartyId,
      cadence: cadence,
      amountPaise: expectedAmountPaise,
    );

    final id = 'ee_${dedupKey}_${expectedDate.millisecondsSinceEpoch}';

    await _db.into(_db.expectedEvents).insertOnConflictUpdate(
          ExpectedEventsCompanion.insert(
            id: id,
            source: source,
            originSmsId: Value(originSmsId),
            seriesId: Value(seriesId),
            counterpartyId: Value(counterpartyId),
            label: label,
            expectedAmountPaise: expectedAmountPaise,
            amountLowPaise: Value(amountLowPaise),
            amountHighPaise: Value(amountHighPaise),
            expectedDate: expectedDate,
            dateWindowDays: Value(dateWindowDays),
            cadence: Value(cadence),
            state: 'expected',
            confidence: confidence,
            dedupKey: dedupKey,
          ),
        );
  }

  /// Query all expected events.
  Future<List<ExpectedEvent>> getExpectedEvents() => _db.select(_db.expectedEvents).get();

  /// Reconciles expected events against actual debit transactions (T-138c).
  /// Matches a later debit at >= 0.85 into 'fulfilled', preserving both rows.
  /// Past the date window with no match -> 'missed'.
  Future<void> reconcileExpectedEvents({required DateTime today}) async {
    final pendingEvents = await (_db.select(_db.expectedEvents)
          ..where((row) => row.state.equals('expected')))
        .get();

    final allTxns = await (_db.select(_db.transactions)
          ..where((row) => row.direction.equals('debit')))
        .get();

    for (final event in pendingEvents) {
      final windowStart = event.expectedDate.subtract(Duration(days: event.dateWindowDays));
      final windowEnd = event.expectedDate.add(Duration(days: event.dateWindowDays));

      Transaction? match;
      for (final txn in allTxns) {
        final txnDate = DateTime.fromMillisecondsSinceEpoch(txn.ts);
        if (txnDate.isBefore(windowStart) || txnDate.isAfter(windowEnd)) continue;

        final txnPaise = (txn.amount * 100).round();
        final amountMatches = (txnPaise - event.expectedAmountPaise).abs() < 2000 ||
            (event.amountLowPaise != null &&
                event.amountHighPaise != null &&
                txnPaise >= event.amountLowPaise! &&
                txnPaise <= event.amountHighPaise!);

        if (amountMatches) {
          match = txn;
          break;
        }
      }

      if (match != null) {
        await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(event.id))).write(
          ExpectedEventsCompanion(
            state: const Value('fulfilled'),
            fulfilledTxnId: Value(match.id),
          ),
        );
      } else if (today.isAfter(windowEnd)) {
        await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(event.id))).write(
          const ExpectedEventsCompanion(state: Value('missed')),
        );
      }
    }
  }

  /// Snoozes an expected event for [days].
  Future<void> snoozeEvent(String id, {int days = 1}) async {
    final event = await (_db.select(_db.expectedEvents)..where((row) => row.id.equals(id))).getSingleOrNull();
    if (event == null) return;
    await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(id))).write(
      ExpectedEventsCompanion(
        state: const Value('snoozed'),
        expectedDate: Value(event.expectedDate.add(Duration(days: days))),
      ),
    );
  }

  /// Cancels an expected event.
  Future<void> cancelEvent(String id) async {
    await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(id))).write(
      const ExpectedEventsCompanion(state: Value('cancelled')),
    );
  }
}
