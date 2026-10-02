import 'dart:convert';

import '../../core/financial_calendar.dart';
import '../../core/transaction_timestamp.dart';
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
  TransactionCsvExportService({FinancialCalendar? calendar})
      : _calendar = calendar ?? FinancialCalendar();

  final FinancialCalendar _calendar;

  /// Serializes [items] to a CSV byte list suitable for sharing via
  /// `share_plus` or writing to a file.
  ///
  /// Existing column order is preserved, with UTC Offset appended:
  /// Date, Time, Merchant, Category, Amount, Direction, Channel, Account,
  /// Status, Note, Reference, UTC Offset.
  List<int> exportToCsv(List<TransactionListItem> items) {
    final buffer = StringBuffer();

    // UTF-8 BOM for Excel compatibility.
    buffer.write('\uFEFF');

    // Header row.
    buffer.writeln(
      'Date,Time,Merchant,Category,Amount,Currency Code,Currency Symbol,Direction,'
      'Channel,Account,Status,Note,Reference,UTC Offset',
    );

    for (final item in items) {
      final timestamp = formatTransactionTimestamp(
        item.ts,
        calendar: _calendar,
      );

      buffer.writeln(
        [
          _escape(timestamp.date),
          _escape(timestamp.time),
          _escape(item.displayName),
          _escape(item.categoryName ?? ''),
          _escape(item.amount.toStringAsFixed(2)),
          _escape(item.currencyCode ?? ''),
          _escape(item.currencySymbol ?? ''),
          _escape(
            item.direction == TransactionDirection.debit ? 'Debit' : 'Credit',
          ),
          _escape(item.channel),
          _escape(item.accountHint ?? ''),
          _escape(item.status),
          _escape(item.note ?? ''),
          _escape(item.reference ?? ''),
          _escape(timestamp.utcOffset),
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
}
