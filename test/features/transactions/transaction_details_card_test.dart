import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/db/database.dart';
import 'package:paisatrack/features/transactions/detail/transaction_details_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ts = DateTime.utc(2026, 9, 14, 13, 5);

  Transaction txn({
    String? counterpartyVpa,
    String? merchantRaw,
    String? refId,
    String? accountHint,
    double? balanceAfter,
    String? currencyCode,
    String? currencySymbol,
    String channel = 'upi',
    String direction = 'debit',
    String lifecycleState = 'settled',
    String parseSource = 'template',
  }) {
    return Transaction(
      id: 'txn_1',
      ts: ts.millisecondsSinceEpoch,
      amount: 250,
      currencyCode: currencyCode,
      currencySymbol: currencySymbol,
      direction: direction,
      channel: channel,
      accountHint: accountHint,
      merchantRaw: merchantRaw,
      counterpartyVpa: counterpartyVpa,
      balanceAfter: balanceAfter,
      refId: refId,
      parseSource: parseSource,
      confidenceJson: '{}',
      status: 'confirmed',
      isDeleted: false,
      isNotTransaction: false,
      isAnalyticsExcluded: false,
      lifecycleState: lifecycleState,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  Map<String, String> rowsOf(List<TransactionDetailRow> rows) =>
      {for (final row in rows) row.label: row.value};

  group('transactionDetailRows', () {
    test('lists every stored field with human labels', () {
      final rows = rowsOf(
        transactionDetailRows(
          txn(
            counterpartyVpa: 'payzomato@hdfcbank',
            merchantRaw: 'ZOMATO LTD',
            refId: '624512345678',
            accountHint: 'XX1234',
            balanceAfter: 10450.5,
            currencyCode: 'INR',
            currencySymbol: 'Rs.',
            lifecycleState: 'pending',
          ),
          title: 'Zomato',
          paymentSourceName: 'HDFC savings',
        ),
      );

      expect(rows['UPI ID / VPA'], 'payzomato@hdfcbank');
      expect(rows['Payee in SMS'], 'ZOMATO LTD');
      expect(rows['Reference / RRN'], '624512345678');
      expect(rows['Channel'], 'UPI');
      expect(rows['Account or card'], 'XX1234');
      expect(rows['Payment source'], 'HDFC savings');
      expect(rows['Direction'], 'Debit (money out)');
      expect(rows['Date and time'], isNotEmpty);
      expect(rows['Balance after'], '₹10,450.50');
      expect(rows['Currency'], 'INR');
      expect(rows['Status'], 'Pending');
      expect(rows['Parsed by'], 'Template match');
    });

    test('shows only present fields and never invents values', () {
      final rows = rowsOf(
        transactionDetailRows(
          txn(merchantRaw: 'Zomato'),
          title: 'Zomato',
        ),
      );

      expect(rows.keys, [
        'Channel',
        'Direction',
        'Amount',
        'Date and time',
        'Parsed by',
      ]);
    });

    test('keeps an unknown currency symbol unknown', () {
      final rows = rowsOf(
        transactionDetailRows(
          txn(balanceAfter: 12, currencySymbol: r'$'),
          title: 'Shop',
        ),
      );
      expect(rows['Balance after'], r'$12.00 (currency unknown)');
      expect(rows['Currency'], r'$ (ISO code unknown)');
    });
  });

  test('only the curated identifiers are copyable', () {
    final rows = transactionDetailRows(
      txn(
        counterpartyVpa: 'payzomato@hdfcbank',
        merchantRaw: 'ZOMATO LTD',
        refId: '624512345678',
        accountHint: 'XX1234',
        balanceAfter: 10450.5,
        currencyCode: 'INR',
        lifecycleState: 'pending',
      ),
      title: 'Zomato',
      paymentSourceName: 'HDFC savings',
    );

    expect(
      rows.where((row) => row.copyable).map((row) => row.label).toSet(),
      {
        'UPI ID / VPA',
        'Reference / RRN',
        'Account or card',
        'Amount',
        'Date and time',
      },
    );
  });

  Future<void> pumpCard(
    WidgetTester tester,
    Transaction transaction, {
    Size size = const Size(402, 874),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransactionDetailsCard(
              transaction: transaction,
              title: 'Zomato',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('copy action puts the value on the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await pumpCard(tester, txn(counterpartyVpa: 'payzomato@hdfcbank'));

    expect(find.text('TRANSACTION DETAILS'), findsOneWidget);
    expect(find.text('payzomato@hdfcbank'), findsOneWidget);
    final copy = find.byTooltip('Copy UPI ID / VPA');
    final copyButton = find.ancestor(
      of: copy,
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(copyButton).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(copyButton).width, greaterThanOrEqualTo(48));
    await tester.tap(copy);
    await tester.pump();

    expect(copied, ['payzomato@hdfcbank']);
    expect(find.text('Copied UPI ID / VPA'), findsOneWidget);
    expect(
      find.bySemanticsLabel('UPI ID / VPA: payzomato@hdfcbank'),
      findsOneWidget,
    );
  });

  testWidgets('VPA row keeps copy and opens a QR at 320dp and 2x text',
      (tester) async {
    await pumpCard(
      tester,
      txn(counterpartyVpa: 'shop.name@bank'),
      size: const Size(320, 568),
      textScale: 2,
    );

    expect(find.byTooltip('Copy UPI ID / VPA'), findsOneWidget);
    expect(find.byTooltip('Show UPI QR'), findsOneWidget);
    await tester.tap(find.byTooltip('Show UPI QR'));
    await tester.pumpAndSettle();
    expect(find.text('UPI QR code'), findsOneWidget);
    expect(find.text('Zomato'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      'shop.name@bank',
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close QR code'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Copy UPI ID / VPA'), findsOneWidget);
  });

  testWidgets('invalid VPA preserves copy but hides QR action', (tester) async {
    await pumpCard(tester, txn(counterpartyVpa: 'bad vpa@bank'));

    expect(find.text('bad vpa@bank'), findsOneWidget);
    expect(find.byTooltip('Copy UPI ID / VPA'), findsOneWidget);
    expect(find.byTooltip('Show UPI QR'), findsNothing);
  });

  testWidgets('fits 2.0x text in landscape without overflow', (tester) async {
    await pumpCard(
      tester,
      txn(
        counterpartyVpa: 'zomato.eternaltsp.payu@hdfcbank',
        merchantRaw: 'ZOMATO ETERNAL LIMITED GURGAON',
        refId: '624512345678',
        accountHint: 'XX1234',
        balanceAfter: 1234567.89,
        currencyCode: 'INR',
      ),
      size: const Size(964, 434),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('zomato.eternaltsp.payu@hdfcbank'), findsOneWidget);
  });
}
