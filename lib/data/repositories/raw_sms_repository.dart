import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}

/// Repository singleton, keyed by the resolved [AppDatabase] instance.
final rawSmsRepositoryProvider = Provider.family<RawSmsRepository, AppDatabase>(
  (ref, database) => RawSmsRepository(database),
);
