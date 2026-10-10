// TEMPORARY STUB: replaced by the real implementation at merge.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

enum TransactionSmsRole { primary, duplicate, supporting }

class TransactionSmsMessage {
  const TransactionSmsMessage({
    required this.smsId,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.role,
    this.kind,
  });

  final String smsId;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final TransactionSmsRole role;
  final String? kind;
}

class TransactionSmsRepository {
  TransactionSmsRepository(this._db);

  // ignore: unused_field
  final AppDatabase _db;

  Future<List<TransactionSmsMessage>> messagesFor(String transactionId) async =>
      const [];
}

final transactionSmsMessagesProvider =
    FutureProvider.family<List<TransactionSmsMessage>, String>(
        (ref, transactionId) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return TransactionSmsRepository(db).messagesFor(transactionId);
});
