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

/// Writes the debug CSV export to a user-selected document.
final transactionCsvExportProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final database = await ref.watch(appDatabaseProvider.future);
  final bytes = await TransactionCsvExporter(database).exportCsvBytes();
  return ref.read(systemDocumentGatewayProvider).saveDocument(
        suggestedName: TransactionCsvExporter.fileName,
        mimeType: 'text/csv',
        bytes: bytes,
      );
});

/// Debug-only plaintext CSV export of all non-deleted transactions.
///
/// Privacy: writes normalized, sensitive plaintext (merchant, amount,
/// account hint, reference) to a user-selected document. The UI entry point
/// MUST stay behind the kDebugMode guard on the dev screen and MUST warn
/// before writing. This is NOT the user-facing encrypted export (T-043).
class TransactionCsvExporter {
  const TransactionCsvExporter(this._database);

  static const fileName = 'transactions_export.csv';

  final AppDatabase _database;

  Future<String> serializeCsv() async {
    final rows = await (_database.select(_database.transactions)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.ts)]))
        .get();
    final categories = await _database.select(_database.categories).get();
    final categoryNames = {for (final c in categories) c.id: c.name};

    final buffer = StringBuffer();
    buffer.write(
      'Date,Merchant,Amount,Direction,Channel,Category,Account,Reference,Status\r\n',
    );

    for (final row in rows) {
      final local =
          DateTime.fromMillisecondsSinceEpoch(row.ts, isUtc: true).toLocal();
      final date = _escapeCsv(
        '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}',
      );
      final merchant = _escapeCsv(row.merchantRaw ?? '');
      final amount = _escapeCsv(row.amount.toStringAsFixed(2));
      final direction = _escapeCsv(row.direction);
      final channel = _escapeCsv(row.channel);
      final category = _escapeCsv(categoryNames[row.categoryId] ?? '');
      final account = _escapeCsv(row.accountHint ?? '');
      final ref = _escapeCsv(row.refId ?? '');
      final status = _escapeCsv(row.status);

      buffer.write(
        '$date,$merchant,$amount,$direction,$channel,$category,$account,$ref,$status\r\n',
      );
    }
    return buffer.toString();
  }

  /// Quotes per RFC 4180 and neutralizes spreadsheet formula evaluation.
  ///
  /// Merchant/reference/account text originates from third-party SMS, so a
  /// leading =, +, -, or @ would execute as a formula in Excel/Sheets on open
  /// (e.g. =HYPERLINK/WEBSERVICE exfiltrating the row). Prefixing a single
  /// quote is the standard mitigation and is stripped by spreadsheet importers.
  static String _escapeCsv(String field) {
    var value = field;
    if (value.isNotEmpty && '=+-@\t\r'.contains(value[0])) {
      value = "'$value";
    }
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<Uint8List> exportCsvBytes() async {
    final csvStr = await serializeCsv();
    return Uint8List.fromList(utf8.encode('\uFEFF$csvStr'));
  }
}
