import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/database_provider.dart';

/// Why a raw SMS is shown on a transaction's detail screen.
enum TransactionSmsRole { primary, duplicate, supporting }

/// One raw SMS shown for a transaction.
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

  /// For supporting messages: `dividend`, `rd_instalment`, `emi_notice`,
  /// `collect_request`, or `related`. Null otherwise.
  final String? kind;
}

/// Reads every retained SMS that describes one transaction (ADR 0032) and
/// records supporting-message links.
class TransactionSmsRepository {
  TransactionSmsRepository(this._db);

  final AppDatabase _db;

  /// Primary SMS first, then duplicates (rows whose `duplicate_of_txn_id` is
  /// [transactionId], and, when this row is itself a duplicate, its canonical
  /// row's SMS), then supporting links, each group ordered by receive time.
  /// Only raw SMS rows that still exist are returned, once each.
  Future<List<TransactionSmsMessage>> messagesFor(String transactionId) async {
    final transaction = await (_db.select(_db.transactions)
          ..where((row) => row.id.equals(transactionId)))
        .getSingleOrNull();
    if (transaction == null) return const [];
    final canonicalId = transaction.duplicateOfTxnId;

    final primaryIds = <String>[
      if (transaction.smsId != null) transaction.smsId!,
    ];

    final duplicateRows = await (_db.select(_db.transactions)
          ..where((row) => row.duplicateOfTxnId.equals(transactionId)))
        .get();
    final duplicateIds = <String>[];
    if (canonicalId != null) {
      final canonical = await (_db.select(_db.transactions)
            ..where((row) => row.id.equals(canonicalId)))
          .getSingleOrNull();
      if (canonical?.smsId != null) duplicateIds.add(canonical!.smsId!);
    }
    duplicateIds.addAll(
      duplicateRows.map((row) => row.smsId).whereType<String>(),
    );

    final linkedTransactionIds = [
      transactionId,
      if (canonicalId != null) canonicalId,
    ];
    final links = await (_db.select(_db.smsTransactionLinks)
          ..where((row) => row.transactionId.isIn(linkedTransactionIds)))
        .get();
    final supportingKinds = <String, String>{};
    for (final link in links) {
      supportingKinds.putIfAbsent(link.smsId, () => link.kind);
    }

    final allIds = {...primaryIds, ...duplicateIds, ...supportingKinds.keys};
    if (allIds.isEmpty) return const [];
    final rawRows = await (_db.select(_db.rawSms)
          ..where((row) => row.id.isIn(allIds)))
        .get();
    final rawById = {for (final row in rawRows) row.id: row};

    final seen = <String>{};
    List<TransactionSmsMessage> group(
      Iterable<String> ids,
      TransactionSmsRole role,
    ) {
      final messages = <TransactionSmsMessage>[];
      for (final id in ids) {
        final raw = rawById[id];
        if (raw == null || !seen.add(id)) continue;
        messages.add(
          TransactionSmsMessage(
            smsId: raw.id,
            sender: raw.sender,
            body: raw.body,
            receivedAt: raw.receivedAt,
            role: role,
            kind: role == TransactionSmsRole.supporting
                ? supportingKinds[id]
                : null,
          ),
        );
      }
      messages.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      return messages;
    }

    return [
      ...group(primaryIds, TransactionSmsRole.primary),
      ...group(duplicateIds, TransactionSmsRole.duplicate),
      ...group(supportingKinds.keys, TransactionSmsRole.supporting),
    ];
  }

  /// Whether [smsId] already has a link to any transaction.
  Future<bool> hasLink(String smsId) async {
    final row = await (_db.selectOnly(_db.smsTransactionLinks)
          ..addColumns([_db.smsTransactionLinks.smsId])
          ..where(_db.smsTransactionLinks.smsId.equals(smsId))
          ..limit(1))
        .getSingleOrNull();
    return row != null;
  }

  /// Records [smsId] as supporting [transactionId]. Idempotent: an existing
  /// link for the pair is left untouched. Returns whether a row was added.
  Future<bool> recordLink({
    required String smsId,
    required String transactionId,
    required String kind,
    required String basis,
    double confidence = 1.0,
    DateTime? now,
  }) async {
    final existing = await (_db.selectOnly(_db.smsTransactionLinks)
          ..addColumns([_db.smsTransactionLinks.smsId])
          ..where(
            _db.smsTransactionLinks.smsId.equals(smsId) &
                _db.smsTransactionLinks.transactionId.equals(transactionId),
          )
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) return false;
    await _db.into(_db.smsTransactionLinks).insert(
          SmsTransactionLinksCompanion.insert(
            smsId: smsId,
            transactionId: transactionId,
            kind: kind,
            basis: basis,
            confidence: Value(confidence),
            createdAt: (now ?? DateTime.now()).toUtc(),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return true;
  }
}

/// Every retained SMS for one transaction, for the detail screen.
final transactionSmsMessagesProvider =
    FutureProvider.family<List<TransactionSmsMessage>, String>(
  (ref, transactionId) async {
    final database = await ref.watch(appDatabaseProvider.future);
    return TransactionSmsRepository(database).messagesFor(transactionId);
  },
);
