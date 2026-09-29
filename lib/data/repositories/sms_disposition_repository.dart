import 'package:drift/drift.dart';

import '../../core/financial_calendar.dart';
import '../db/database.dart';
import '../../intelligence/anomaly_detector.dart';
import '../../intelligence/burn_rate_forecaster.dart';
import '../../intelligence/insights_engine.dart';
import '../../intelligence/recurring_detector.dart';
import 'expected_event_repository.dart';
import 'payee_evidence_repository.dart';
import 'recurring_status_memory.dart';

/// Persists a user's correction without retaining SMS content.
class SmsDispositionRepository {
  const SmsDispositionRepository(this.database);

  final AppDatabase database;

  Future<void> markNotTransaction(
    Transaction transaction,
  ) async {
    final smsId = transaction.smsId;
    if (smsId == null) throw StateError('Transaction has no SMS identity');
    await database.transaction(() async {
      await database.into(database.smsDispositions).insertOnConflictUpdate(
            SmsDispositionsCompanion.insert(
              smsId: smsId,
              transactionId: transaction.id,
              disposition: 'not_transaction',
              createdAt: DateTime.now().toUtc(),
            ),
          );
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(transaction.id)))
          .write(
        TransactionsCompanion(
          isNotTransaction: const Value(true),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await (database.update(database.expectedEvents)
            ..where((row) => row.fulfilledTxnId.equals(transaction.id)))
          .write(
        const ExpectedEventsCompanion(
          fulfilledTxnId: Value(null),
          state: Value('expected'),
        ),
      );
      await (database.delete(database.payeeEvidence)
            ..where((row) => row.transactionId.equals(transaction.id)))
          .go();
    });
    await refreshDerivedReads();
  }

  Future<void> restore(String smsId) async {
    await database.transaction(() async {
      final disposition = await (database.select(database.smsDispositions)
            ..where((row) => row.smsId.equals(smsId)))
          .getSingleOrNull();
      if (disposition == null) return;
      await (database.update(database.transactions)
            ..where((row) => row.id.equals(disposition.transactionId)))
          .write(
        TransactionsCompanion(
          isNotTransaction: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      final transaction = await (database.select(database.transactions)
            ..where((row) => row.id.equals(disposition.transactionId)))
          .getSingleOrNull();
      if (transaction != null) {
        final evidence = PayeeEvidenceRepository.companionsFor(
          transactionId: transaction.id,
          merchantRaw: transaction.merchantRaw,
          counterpartyVpa: transaction.counterpartyVpa,
        );
        if (evidence.isNotEmpty) {
          await database.batch((batch) {
            batch.insertAll(
              database.payeeEvidence,
              evidence,
              mode: InsertMode.insertOrReplace,
            );
          });
        }
      }
      await (database.delete(database.smsDispositions)
            ..where((row) => row.smsId.equals(smsId)))
          .go();
    });
    final today = FinancialCalendar().localDate(DateTime.now());
    await ExpectedEventRepository(database).reconcileExpectedEvents(
      today: DateTime.utc(today.year, today.month, today.day),
    );
    await refreshDerivedReads();
  }

  Future<void> refreshDerivedReads() async {
    final previousSeries =
        await database.select(database.recurringSeries).get();
    await database.delete(database.recurringSeries).go();
    await RecurringDetector(database).run();
    await AnomalyDetector(database).run();
    await BurnRateForecaster(database).run();
    await InsightsEngine(database).run();
    final previousStatus = await RecurringStatusMemory.read(database);
    for (final series in previousSeries) {
      if (!RecurringStatusMemory.isUserControlled(series.status)) continue;
      final key = RecurringStatusMemory.identity(series);
      previousStatus[key] = series.status;
      await RecurringStatusMemory.remember(database, key, series.status);
    }
    for (final series
        in await database.select(database.recurringSeries).get()) {
      final key = RecurringStatusMemory.identity(series);
      final status = previousStatus[key];
      if (status == null) continue;
      await (database.update(database.recurringSeries)
            ..where((row) => row.id.equals(series.id)))
          .write(RecurringSeriesCompanion(status: Value(status)));
    }
  }

  Future<List<({Transaction transaction, String smsId})>>
      listMarkedTransactions() async {
    final query = database.select(database.transactions).join([
      innerJoin(
        database.smsDispositions,
        database.smsDispositions.transactionId
            .equalsExp(database.transactions.id),
      ),
    ])
      ..where(database.transactions.isNotTransaction.equals(true))
      ..orderBy([OrderingTerm.desc(database.transactions.updatedAt)]);
    final rows = await query.get();
    return rows
        .map(
          (row) => (
            transaction: row.readTable(database.transactions),
            smsId: row.readTable(database.smsDispositions).smsId,
          ),
        )
        .toList(growable: false);
  }

  Future<bool> isMarked(String smsId) async =>
      await (database.select(database.smsDispositions)
            ..where((row) => row.smsId.equals(smsId)))
          .getSingleOrNull() !=
      null;
}
