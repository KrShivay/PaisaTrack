import 'dart:convert';

import '../../data/models/normalized_transaction_record.dart';
import '../../data/repositories/transaction_repository.dart';

/// Release-safe CSV export service for PaisaTrack activity.
///
/// Security invariants:
///   - Excludes raw SMS body, confidence JSON, internal IDs, and deleted rows.
///   - Neutralizes formula injection: cells starting with `=`, `+`, `-`, `@`,
///     tab, or carriage return are prefixed with a single-quote.
///   - Exported file uses `.csv` extension with `text/csv` MIME type.
class TransactionCsvExportService {
  const TransactionCsvExportService();

  /// Serializes [items] to a CSV byte list suitable for sharing via
  /// `share_plus` or writing to a file.
  ///
  /// Column order matches the design addendum export contract:
  /// Date, Time, Merchant, Category, Amount, Direction, Channel, Account,
  /// Status, Note, Reference.
  List<int> exportToCsv(List<TransactionListItem> items) {
    final buffer = StringBuffer();

    // UTF-8 BOM for Excel compatibility.
    buffer.write('\uFEFF');

    // Header row.
    buffer.writeln(
      'Date,Time,Merchant,Category,Amount,Direction,'
      'Channel,Account,Status,Note,Reference',
    );

    for (final item in items) {
      final date = item.ts.toLocal();
      final dateStr = '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
      final timeStr =
          '${_pad(date.hour)}:${_pad(date.minute)}:${_pad(date.second)}';

      buffer.writeln(
        [
          _escape(dateStr),
          _escape(timeStr),
          _escape(item.displayName),
          _escape(item.categoryName ?? ''),
          _escape(item.amount.toStringAsFixed(2)),
          _escape(
            item.direction == TransactionDirection.debit ? 'Debit' : 'Credit',
          ),
          _escape(item.channel),
          _escape(item.accountHint ?? ''),
          _escape(item.status),
          _escape(item.note ?? ''),
          _escape(item.reference ?? ''),
        ].join(','),
      );
    }

    return utf8.encode(buffer.toString());
  }

  /// Escapes a CSV cell value:
  ///   1. Neutralizes formula injection by prefixing dangerous first characters.
  ///   2. Wraps in double-quotes if the value contains commas, quotes, or
  ///      newlines, doubling any internal double-quotes.
  static String _escape(String value) {
    if (value.isEmpty) return '';

    var safe = value;

    // Neutralize formula injection characters.
    const dangerousFirstChars = {'=', '+', '-', '@', '\t', '\r'};
    if (dangerousFirstChars.contains(safe[0])) {
      safe = "'$safe";
    }

    // Standard CSV quoting.
    if (safe.contains(',') ||
        safe.contains('"') ||
        safe.contains('\n') ||
        safe.contains('\r')) {
      safe = '"${safe.replaceAll('"', '""')}"';
    }

    return safe;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
