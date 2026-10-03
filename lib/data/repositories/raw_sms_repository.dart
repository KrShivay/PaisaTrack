import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/parser_version.dart';
import '../../core/constants.dart';
import '../db/database.dart';

/// A raw SMS that has not yet produced a transaction (parse failure or not
/// yet processed), surfaced on the developer diagnostics screen.
class UnparsedSms {
  const UnparsedSms({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
}

/// Content-free counts for retained raw SMS rows that could not be processed.
///
/// The query that creates this value selects only reason metadata and expiry;
/// it never loads bodies, senders, or message identifiers.
class RetainedSmsFailureSummary {
  const RetainedSmsFailureSummary({required this.reasonCounts});

  final Map<String, int> reasonCounts;

  int get total => reasonCounts.values.fold(0, (sum, count) => sum + count);

  int countFor(String reason) => reasonCounts[reason] ?? 0;
}

/// Source-SMS retention (ADR 0021).
///
/// The SMS behind a transaction or a "not a transaction" disposition is
/// provenance and is kept for as long as that record exists. Every other raw
/// SMS (unparsed, unreadable, never linked) expires when its `purge_after`
/// passes or it is [AppConstants.rawSmsRetentionDays] old, whichever is
/// first; the age cap also covers rows captured under the old 30-day rule.
abstract final class RawSmsRetention {
  /// Whether a raw SMS row backs a transaction or a disposition.
  static Expression<bool> isLinked(AppDatabase database) {
    final transactionSmsIds = database.selectOnly(database.transactions)
      ..addColumns([database.transactions.smsId])
      ..where(database.transactions.smsId.isNotNull());
    final dispositionSmsIds = database.selectOnly(database.smsDispositions)
      ..addColumns([database.smsDispositions.smsId]);
    return database.rawSms.id.isInQuery(transactionSmsIds) |
        database.rawSms.id.isInQuery(dispositionSmsIds);
  }

  static Expression<bool> _isExpired(AppDatabase database, DateTime now) =>
      database.rawSms.purgeAfter.isSmallerOrEqualValue(now) |
      database.rawSms.receivedAt.isSmallerOrEqualValue(
        now.subtract(const Duration(days: AppConstants.rawSmsRetentionDays)),
      );

  /// Rows that survive retention: linked provenance plus unexpired SMS.
  static Expression<bool> isRetained(AppDatabase database, DateTime now) =>
      isLinked(database) | _isExpired(database, now).not();

  /// Deletes expired unlinked raw SMS and clears expected-event origins that
  /// pointed at them (no foreign key guards that column). Linked rows are
  /// never touched.
  static Future<void> purgeExpiredUnlinked(
    AppDatabase database, {
    required DateTime now,
  }) async {
    await (database.delete(database.rawSms)
          ..where((_) => isRetained(database, now).not()))
        .go();
    final rawIds = database.selectOnly(database.rawSms)
      ..addColumns([database.rawSms.id]);
    await (database.update(database.expectedEvents)
          ..where(
            (row) =>
                row.originSmsId.isNotNull() &
                row.originSmsId.isNotInQuery(rawIds),
          ))
        .write(const ExpectedEventsCompanion(originSmsId: Value(null)));
  }
}

/// Reads raw SMS rows that failed to parse into a transaction.
class RawSmsRepository {
  const RawSmsRepository(this._database);

  final AppDatabase _database;

  /// Watches unprocessed raw SMS, newest first.
  Stream<List<UnparsedSms>> watchUnparsed() {
    final query = _database.select(_database.rawSms)
      ..where((row) => row.processed.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.receivedAt)]);

    return query.watch().map(
          (rows) => rows
              .map(
                (row) => UnparsedSms(
                  id: row.id,
                  sender: row.sender,
                  body: row.body,
                  receivedAt: row.receivedAt,
                ),
              )
              .toList(growable: false),
        );
  }

  /// Watches only unprocessed failures that are still inside raw-SMS
  /// retention. Expired rows are excluded even if nightly cleanup has not run.
  Stream<RetainedSmsFailureSummary> watchRetainedFailures({DateTime? now}) {
    final failureReason = _database.rawSms.failureReason;
    final query = _database.selectOnly(_database.rawSms)
      ..addColumns([failureReason])
      ..where(
        _database.rawSms.processed.equals(false) &
            failureReason.isIn(const [
              SmsFailureReason.unparsed,
              SmsFailureReason.processingError,
            ]) &
            RawSmsRetention.isRetained(_database, now ?? DateTime.now()),
      );

    return query.watch().map((rows) {
      final counts = <String, int>{
        SmsFailureReason.unparsed: 0,
        SmsFailureReason.processingError: 0,
      };
      for (final row in rows) {
        final reason = row.read(failureReason);
        if (reason != null && counts.containsKey(reason)) {
          counts[reason] = counts[reason]! + 1;
        }
      }
      return RetainedSmsFailureSummary(reasonCounts: counts);
    });
  }
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final rawSmsRepositoryProvider = Provider.family<RawSmsRepository, AppDatabase>(
  (ref, database) => RawSmsRepository(database),
);
