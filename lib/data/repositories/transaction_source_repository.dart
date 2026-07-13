import 'package:drift/drift.dart';

import '../db/database.dart';

/// User-facing provenance for a transaction.
///
/// Raw SMS fields are nullable because retention cleanup can remove the source
/// message while the normalized transaction remains available.
class TransactionSourceInfo {
  const TransactionSourceInfo({
    required this.counterpartyVpa,
    required this.smsSender,
    required this.smsBody,
    required this.smsReceivedAt,
  });

  final String? counterpartyVpa;
  final String? smsSender;
  final String? smsBody;
  final DateTime? smsReceivedAt;
}

class TransactionSourceRepository {
  const TransactionSourceRepository(this._database);

  final AppDatabase _database;

  Stream<TransactionSourceInfo?> watch(String txnId) {
    final query = _database.select(_database.transactions).join([
      leftOuterJoin(
        _database.rawSms,
        _database.rawSms.id.equalsExp(_database.transactions.smsId),
      ),
    ])
      ..where(_database.transactions.id.equals(txnId));

    return query.watch().map((rows) {
      if (rows.isEmpty) return null;
      final txn = rows.first.readTable(_database.transactions);
      final sms = rows.first.readTableOrNull(_database.rawSms);
      return TransactionSourceInfo(
        counterpartyVpa: txn.counterpartyVpa,
        smsSender: sms?.sender,
        smsBody: sms?.body,
        smsReceivedAt: sms?.receivedAt,
      );
    });
  }
}
