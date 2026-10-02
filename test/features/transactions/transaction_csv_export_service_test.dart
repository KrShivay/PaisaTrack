import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/financial_calendar.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';
import 'package:paisatrack/data/repositories/transaction_repository.dart';
import 'package:paisatrack/features/transactions/transaction_csv_export_service.dart';

void main() {
  group('TransactionCsvExportService', () {
    late TransactionCsvExportService service;

    setUp(() {
      service = TransactionCsvExportService();
    });

    TransactionListItem makeItem({
      String id = 'txn_1',
      DateTime? ts,
      String displayName = 'Swiggy',
      double amount = 450.0,
      TransactionDirection direction = TransactionDirection.debit,
      String channel = 'UPI',
      String? accountHint = 'HDFC ****1234',
      String? note,
      String? reference,
      String status = 'confirmed',
      String? categoryName = 'Food & Dining',
      String? currencyCode,
      String? currencySymbol,
    }) =>
        TransactionListItem(
          id: id,
          ts: ts ?? DateTime.utc(2026, 7, 26, 12, 30, 0),
          amount: amount,
          currencyCode: currencyCode,
          currencySymbol: currencySymbol,
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
      expect(
        csv,
        contains(
          'Date,Time,Merchant,Category,Amount,Currency Code,Currency Symbol,Direction',
        ),
      );
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

    test('exports local day, time, and offset without reordering columns', () {
      const localCalendar = FinancialCalendar.fixed(
        Duration(hours: 5, minutes: 30),
      );
      final localService = TransactionCsvExportService(
        calendar: localCalendar,
      );
      final csv = utf8.decode(
        localService.exportToCsv([
          makeItem(ts: DateTime.utc(2026, 7, 25, 19)),
          makeItem(id: 'txn_2', ts: DateTime.utc(2026, 7, 26, 18, 29)),
        ]),
      );
      final lines = csv.trim().split('\n');

      expect(lines.first, endsWith('Reference,UTC Offset'));
      expect(lines[1], startsWith('2026-07-26,00:30:00,'));
      expect(lines[1], endsWith(',UTC+05:30'));
      expect(lines[2], startsWith('2026-07-26,23:59:00,'));
      expect(lines[2], endsWith(',UTC+05:30'));
    });

    test('formats an injected negative UTC offset', () {
      final localService = TransactionCsvExportService(
        calendar: const FinancialCalendar.fixed(Duration(hours: -4)),
      );
      final csv = utf8.decode(
        localService.exportToCsv([
          makeItem(ts: DateTime.utc(2026, 7, 26, 4, 30)),
        ]),
      );

      expect(csv, contains('2026-07-26,00:30:00,'));
      expect(csv, endsWith(',UTC-04:00\n'));
    });

    test('exports source currency alongside nominal amount', () {
      final csv = utf8.decode(
        service.exportToCsv([makeItem(currencySymbol: r'$')]),
      );
      expect(csv, contains('450.00,,\$,Debit'));
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
