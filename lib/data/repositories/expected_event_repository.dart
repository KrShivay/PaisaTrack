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
}
