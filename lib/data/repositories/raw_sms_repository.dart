import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/parser_version.dart';
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
            _database.rawSms.purgeAfter
                .isBiggerThanValue(now ?? DateTime.now()),
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
