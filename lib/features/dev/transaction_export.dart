import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/db/database.dart';
import '../../data/db/database_provider.dart';

/// Debug-only export of all transactions as plain JSON, used for the T-034
/// bank-statement reconciliation (`scripts/reconcile_statement.py
/// --transactions <file>`).
///
/// Privacy: the export is written to the app-private documents directory
/// (`/data/data/com.paisatrack/app_flutter/`), never external storage, and the
/// UI entry point is compiled out of release builds (kDebugMode guard on the
/// dev screen). Retrieval is via adb `run-as`, which only works on debuggable
/// builds. This is NOT the user-facing encrypted export (Phase 2, T-043).
class TransactionJsonExporter {
  const TransactionJsonExporter(this._database);

  static const fileName = 'transactions_export.json';

  final AppDatabase _database;

  /// Serializes every transaction row (including suppressed duplicates,
  /// flagged via `is_deleted`) in the reconciliation schema.
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
          'balance_after': row.balanceAfter,
          'ref_id': row.refId,
          'parse_source': row.parseSource,
          'status': row.status,
          'is_deleted': row.isDeleted,
        },
    ];
  }

  /// Writes the export into [directory] and returns the created file.
  Future<File> exportTo(Directory directory) async {
    final records = await serializeAll();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(records));
    return file;
  }
}

/// Runs the export into the app documents directory and returns the file path.
final transactionJsonExportProvider = FutureProvider.autoDispose<String>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final directory = await getApplicationDocumentsDirectory();
  final file = await TransactionJsonExporter(database).exportTo(directory);
  return file.path;
});
