import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transaction_csv_export_service.dart';

void main() {
  group('TransactionCsvExportService', () {
    late TransactionCsvExportService service;

    setUp(() {
      service = const TransactionCsvExportService();
    });

    TransactionListItem makeItem({
      String id = 'txn_1',
      String displayName = 'Swiggy',
      double amount = 450.0,
      TransactionDirection direction = TransactionDirection.debit,
      String channel = 'UPI',
      String? accountHint = 'HDFC ****1234',
      String? note,
      String? reference,
      String status = 'confirmed',
      String? categoryName = 'Food & Dining',
    }) =>
        TransactionListItem(
          id: id,
          ts: DateTime.utc(2026, 7, 26, 12, 30, 0),
          amount: amount,
          direction: direction,
          displayName: displayName,
          categoryName: categoryName,
          categoryId: 'food_cat',
          categoryIcon: 'food',
          channel: channel,
          accountHint: accountHint,
          note: note,
          reference: reference,
          status: status,
        );

    test('generates valid CSV header and data row', () {
      final item = makeItem(note: 'Lunch', reference: 'REF123');
      final bytes = service.exportToCsv([item]);
      final csv = utf8.decode(bytes);

      // Verify header (after BOM).
      expect(csv, contains('Date,Time,Merchant,Category,Amount,Direction'));
      expect(csv, contains('Channel,Account,Status,Note,Reference'));

      // Verify data row.
      expect(csv, contains('2026-07-26'));
      expect(csv, contains('Swiggy'));
      expect(csv, contains('450.00'));
      expect(csv, contains('Debit'));
      expect(csv, contains('UPI'));
      expect(csv, contains('Food & Dining'));
      expect(csv, contains('Lunch'));
      expect(csv, contains('REF123'));
    });

    test('excludes raw SMS, confidence JSON, and internal IDs', () {
      final bytes = service.exportToCsv([makeItem()]);
      final csv = utf8.decode(bytes);

      // No internal field names should appear.
      expect(csv, isNot(contains('confidenceJson')));
      expect(csv, isNot(contains('parseSource')));
      expect(csv, isNot(contains('txn_1'))); // internal ID excluded
    });

    test('neutralizes formula injection characters', () {
      final items = [
        makeItem(displayName: '=CMD()'),
        makeItem(id: 'txn_2', displayName: '+HYPERLINK("evil")'),
        makeItem(id: 'txn_3', displayName: '@SUM(A1:A10)'),
      ];
      final csv = utf8.decode(service.exportToCsv(items));

      // Each dangerous first character should be prefixed with single-quote.
      expect(csv, contains("'=CMD()"));
      expect(csv, contains("'+HYPERLINK"));
      expect(csv, isNot(contains(',=CMD')));
      expect(csv, isNot(contains(',+HYPERLINK')));
      expect(csv, contains("'@SUM"));
    });

    test('handles empty list gracefully', () {
      final bytes = service.exportToCsv([]);
      final csv = utf8.decode(bytes);

      // Should have header but no data rows.
      expect(csv, contains('Date,Time,Merchant'));
      final lines = csv.trim().split('\n');
      expect(lines.length, equals(1)); // header only
    });

    test('escapes CSV cells with commas and quotes', () {
      final item = makeItem(
        displayName: 'Merchant, Inc.',
        note: 'Said "hello"',
      );
      final csv = utf8.decode(service.exportToCsv([item]));

      // Value with comma should be quoted.
      expect(csv, contains('"Merchant, Inc."'));
      // Value with quotes should be double-quoted inside.
      expect(csv, contains('""hello""'));
    });

    test('credit transactions show Credit direction', () {
      final item = makeItem(direction: TransactionDirection.credit);
      final csv = utf8.decode(service.exportToCsv([item]));

      expect(csv, contains('Credit'));
      expect(csv, isNot(contains('Debit')));
    });

    test('handles null optional fields gracefully', () {
      final item = makeItem(
        accountHint: null,
        note: null,
        reference: null,
        categoryName: null,
      );
      final csv = utf8.decode(service.exportToCsv([item]));

      // Should not crash and should produce a valid row.
      expect(csv, contains('Swiggy'));
      expect(csv, contains('450.00'));
    });
  });
}
