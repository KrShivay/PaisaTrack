import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/system_document_gateway.dart';
import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

/// Debug-only export of all transactions as plain JSON, used for the T-034
/// bank-statement reconciliation (`scripts/reconcile_statement.py
/// --transactions <file>`).
///
/// Privacy: the UI entry point is compiled out of release builds (kDebugMode
/// guard on the dev screen) and warns before writing normalized, sensitive
/// plaintext data to a user-selected document. This is NOT the user-facing
/// encrypted export (Phase 2, T-043).
class TransactionJsonExporter {
  const TransactionJsonExporter(this._database);

  static const fileName = 'transactions_export.json';

  final AppDatabase _database;

  /// Serializes every transaction row (including suppressed duplicates,
  /// flagged via `duplicate_of_txn_id`) in the reconciliation schema.
  Future<List<Map<String, Object?>>> serializeAll() async {
    final rows = await (_database.select(_database.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.ts)]))
        .get();
    return [
      for (final row in rows)
        {
          'id': row.id,
          'ts': row.ts,
          'amount': row.amount,
          'direction': row.direction,
          'channel': row.channel,
          'account_hint': row.accountHint,
          'merchant_raw': row.merchantRaw,
          'counterparty_vpa': row.counterpartyVpa,
          'balance_after': row.balanceAfter,
          'ref_id': row.refId,
          'parse_source': row.parseSource,
          'status': row.status,
          'is_deleted': row.isDeleted,
          'duplicate_of_txn_id': row.duplicateOfTxnId,
        },
    ];
  }

  /// Encodes all transaction rows for a system-selected document destination.
  Future<Uint8List> exportBytes() async {
    final records = await serializeAll();
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(records)),
    );
  }

  /// Writes the export into [directory] and returns the created file.
  Future<File> exportTo(Directory directory) async {
    final records = await serializeAll();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file
        .writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    return file;
  }
}

/// Writes the debug export to a user-selected document.
final transactionJsonExportProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final bytes = await TransactionJsonExporter(database).exportBytes();
  return ref.read(systemDocumentGatewayProvider).saveDocument(
        suggestedName: TransactionJsonExporter.fileName,
        mimeType: 'application/json',
        bytes: bytes,
      );
});
