import 'package:drift/drift.dart';

import '../../capture/supporting_sms_classifier.dart';
import '../db/database.dart';
import '../models/source_currency.dart';
import 'transaction_sms_repository.dart';

/// Repository for managing ExpectedEvents (T-138b).
/// Expected events capture bill-due reminders, mandates, and upcoming obligations.
/// Invariant: Expected events NEVER enter spending totals or transactions.
class ExpectedEventRepository {
  ExpectedEventRepository(
    this._db, {
    SupportingSmsClassifier? supportingClassifier,
  }) : _supportingClassifier = supportingClassifier;

  final AppDatabase _db;
  final SupportingSmsClassifier? _supportingClassifier;

  /// Derive stable deduplication key for one obligation across multiple reminders.
  static String computeDedupKey({
    required String label,
    String? counterpartyId,
    String? cadence,
    required int amountPaise,
    String? currencyCode,
    String? currencySymbol,
  }) {
    final cpty =
        counterpartyId ?? label.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final cad = cadence ?? 'monthly';
    // Group amount into ~100 INR buckets (10000 paise) to absorb minor fee variations
    final roughAmt = (amountPaise / 10000).round();
    final currency = SourceCurrency(
      code: currencyCode,
      symbol: currencySymbol,
    );
    final suffix = currencyCode != null || currencySymbol != null
        ? '_${currency.bucketKey}'
        : '';
    return '${cpty}_${cad}_$roughAmt$suffix';
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
    String? currencyCode,
    String? currencySymbol,
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
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
    );

    final id = 'ee_${dedupKey}_${expectedDate.millisecondsSinceEpoch}';

    // A repeated reminder may arrive after an event was fulfilled, missed, or
    // cancelled. Updating the row would reset that lifecycle state to expected.
    await _db.into(_db.expectedEvents).insert(
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
            currencyCode: Value(currencyCode),
            currencySymbol: Value(currencySymbol),
            expectedDate: expectedDate,
            dateWindowDays: Value(dateWindowDays),
            cadence: Value(cadence),
            state: 'expected',
            confidence: confidence,
            dedupKey: dedupKey,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Query all expected events.
  Future<List<ExpectedEvent>> getExpectedEvents() =>
      _db.select(_db.expectedEvents).get();

  /// Reconciles expected events against actual debit transactions (T-138c).
  /// Exact-identity, amount, and date matches fulfil while preserving both rows.
  /// Past the window with no candidates -> missed; ambiguity stays expected for
  /// review because an eligible debit may represent the obligation.
  Future<void> reconcileExpectedEvents({required DateTime today}) async {
    await _db.transaction(() async {
      final pendingEvents = await (_db.select(_db.expectedEvents)
            ..where((row) => row.state.isIn(['expected', 'snoozed']))
            ..orderBy([
              (row) => OrderingTerm.asc(row.expectedDate),
              (row) => OrderingTerm.asc(row.id),
            ]))
          .get();
      if (pendingEvents.isEmpty) return;

      final fulfilledEvents = await (_db.select(_db.expectedEvents)
            ..where((row) => row.fulfilledTxnId.isNotNull()))
          .get();
      final alreadyLinkedTxnIds =
          fulfilledEvents.map((event) => event.fulfilledTxnId!).toSet();
      final todayStart = _utcDayStart(today);

      // Query each event's narrow indexed timestamp/amount window instead of
      // loading the transaction history. Identity and ambiguity checks remain
      // in Dart because VPAs are normalized case-insensitively here.
      final candidatesByEvent = <String, List<Transaction>>{};
      final eventIdsByTxn = <String, Set<String>>{};
      final hasPotentialMatch = <String, bool>{};
      final canMarkMissed = <String, bool>{};
      for (final event in pendingEvents) {
        final eventCurrency = SourceCurrency(
          code: event.currencyCode,
          symbol: event.currencySymbol,
        );
        final counterparty = _normalizedVpa(event.counterpartyId);
        final bounds = _amountBounds(event);
        if (counterparty.isEmpty || bounds == null) {
          candidatesByEvent[event.id] = const [];
          hasPotentialMatch[event.id] = false;
          canMarkMissed[event.id] = false;
          continue;
        }
        canMarkMissed[event.id] = true;

        final dueDay = _utcDayStart(event.expectedDate);
        final windowDays = event.dateWindowDays < 0 ? 0 : event.dateWindowDays;
        final windowStart = dueDay.subtract(Duration(days: windowDays));
        final windowEndExclusive = dueDay.add(Duration(days: windowDays + 1));
        final candidates = await (_db.select(_db.transactions)
              ..where(
                (row) =>
                    row.direction.equals('debit') &
                    row.lifecycleState.equals('settled') &
                    row.status.isIn(['auto', 'confirmed']) &
                    row.isDeleted.equals(false) &
                    row.isNotTransaction.equals(false) &
                    row.duplicateOfTxnId.isNull() &
                    row.ts.isBiggerOrEqual(
                      Variable<int>(windowStart.millisecondsSinceEpoch),
                    ) &
                    row.ts.isSmallerThan(
                      Variable<int>(windowEndExclusive.millisecondsSinceEpoch),
                    ) &
                    _amountClause(
                      row.amount,
                      bounds,
                    ),
              ))
            .get();
        final identityMatches = candidates.where((txn) {
          final transactionCurrency = SourceCurrency(
            code: txn.currencyCode,
            symbol: txn.currencySymbol,
          );
          return _normalizedVpa(txn.counterpartyVpa) == counterparty &&
              eventCurrency.sameBucket(transactionCurrency);
        }).toList(growable: false);
        candidatesByEvent[event.id] = identityMatches;
        hasPotentialMatch[event.id] = identityMatches.isNotEmpty;
        for (final txn in identityMatches) {
          eventIdsByTxn.putIfAbsent(txn.id, () => <String>{}).add(event.id);
        }
      }

      for (final event in pendingEvents) {
        final candidates = candidatesByEvent[event.id] ?? const [];
        final unclaimed = candidates
            .where((txn) => !alreadyLinkedTxnIds.contains(txn.id))
            .toList(growable: false);
        final match = unclaimed.length == 1 &&
                eventIdsByTxn[unclaimed.single.id]?.length == 1
            ? unclaimed.single
            : null;

        if (match != null) {
          await (_db.update(_db.expectedEvents)
                ..where(
                  (row) =>
                      row.id.equals(event.id) &
                      row.state.equals(event.state) &
                      row.expectedDate.equals(event.expectedDate),
                ))
              .write(
            ExpectedEventsCompanion(
              state: const Value('fulfilled'),
              fulfilledTxnId: Value(match.id),
            ),
          );
          alreadyLinkedTxnIds.add(match.id);
          await _linkOriginSms(event.originSmsId, match.id);
        } else {
          final dueDay = _utcDayStart(event.expectedDate);
          final windowDays =
              event.dateWindowDays < 0 ? 0 : event.dateWindowDays;
          final lastWindowDay = dueDay.add(Duration(days: windowDays));
          if (canMarkMissed[event.id] == true &&
              hasPotentialMatch[event.id] != true &&
              todayStart.isAfter(lastWindowDay)) {
            await (_db.update(_db.expectedEvents)
                  ..where(
                    (row) =>
                        row.id.equals(event.id) &
                        row.state.equals(event.state) &
                        row.expectedDate.equals(event.expectedDate),
                  ))
                .write(const ExpectedEventsCompanion(state: Value('missed')));
          }
        }
      }
    });
  }

  /// Records the reminder SMS behind a fulfilled event as a supporting
  /// message of the transaction that fulfilled it (ADR 0032), so it appears
  /// on the transaction detail screen. Idempotent; a message that is already
  /// linked anywhere keeps its existing link.
  Future<bool> _linkOriginSms(String? originSmsId, String transactionId) async {
    if (originSmsId == null) return false;
    final links = TransactionSmsRepository(_db);
    if (await links.hasLink(originSmsId)) return false;
    final raw = await (_db.select(_db.rawSms)
          ..where((row) => row.id.equals(originSmsId)))
        .getSingleOrNull();
    if (raw == null) return false;
    final kind =
        _supportingClassifier?.classify(raw.body)?.kind.wireName ?? 'related';
    return links.recordLink(
      smsId: originSmsId,
      transactionId: transactionId,
      kind: kind,
      basis: 'expected_event_fulfilled',
      confidence: 0.9,
    );
  }

  /// Backfill for events fulfilled before origin links existed: links each
  /// fulfilled event's still-retained origin SMS. Bounded by [limit]; returns
  /// the number of links written.
  Future<int> linkFulfilledOriginSms({int limit = 500}) async {
    final linkedIds = _db.selectOnly(_db.smsTransactionLinks)
      ..addColumns([_db.smsTransactionLinks.smsId]);
    final events = await (_db.select(_db.expectedEvents)
          ..where(
            (row) =>
                row.fulfilledTxnId.isNotNull() &
                row.originSmsId.isNotNull() &
                row.originSmsId.isNotInQuery(linkedIds),
          )
          ..limit(limit))
        .get();
    var written = 0;
    for (final event in events) {
      if (await _linkOriginSms(event.originSmsId, event.fulfilledTxnId!)) {
        written++;
      }
    }
    return written;
  }

  static String _normalizedVpa(String? value) =>
      value?.trim().toLowerCase() ?? '';

  static DateTime _utcDayStart(DateTime value) {
    final utc = value.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static (int, int)? _amountBounds(ExpectedEvent event) {
    final low = event.amountLowPaise;
    final high = event.amountHighPaise;
    if (low != null || high != null) {
      if (low != null && high != null && low > 0 && high >= low) {
        return (low, high);
      }
      return null;
    }
    if (event.expectedAmountPaise <= 0) return null;
    // Transaction.amount is still REAL; one paisa absorbs its conversion
    // rounding while remaining far tighter than the old ₹20 tolerance.
    return (event.expectedAmountPaise - 1, event.expectedAmountPaise + 1);
  }

  static Expression<bool> _amountClause(
    Expression<double> amount,
    (int, int) bounds,
  ) {
    final lowRupees = bounds.$1 / 100;
    final highRupees = bounds.$2 / 100;
    return (amount.isBiggerOrEqual(
          Variable<double>(lowRupees),
        ) &
        amount.isSmallerOrEqual(
          Variable<double>(highRupees),
        ));
  }

  /// Snoozes an expected event for [days].
  Future<void> snoozeEvent(String id, {int days = 1}) async {
    final event = await (_db.select(_db.expectedEvents)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    if (event == null) return;
    await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(id)))
        .write(
      ExpectedEventsCompanion(
        state: const Value('snoozed'),
        expectedDate: Value(event.expectedDate.add(Duration(days: days))),
      ),
    );
  }

  /// Cancels an expected event.
  Future<void> cancelEvent(String id) async {
    await (_db.update(_db.expectedEvents)..where((row) => row.id.equals(id)))
        .write(
      const ExpectedEventsCompanion(state: Value('cancelled')),
    );
  }
}
