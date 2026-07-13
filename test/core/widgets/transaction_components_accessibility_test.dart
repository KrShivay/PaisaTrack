import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/transaction_components.dart';
import 'package:paisatrack/data/models/normalized_transaction_record.dart';

void main() {
  testWidgets('large text keeps long merchant and full INR amount usable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: TransactionTile(
              merchantName:
                  'Bharat Petroleum Corporation Limited Merchant Terminal',
              amount: 123456789.01,
              direction: TransactionDirection.debit,
              categoryLabel: 'Transport',
              timeLabel: 'Today · 3:54 PM',
              accountLabel: 'HDFC ••6265',
              statusLabel: 'Needs review',
            ),
          ),
        ),
      ),
    );

    expect(find.text('-₹12,34,56,789.01'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final semantics = tester.getSemantics(find.byType(TransactionTile));
    expect(semantics.label, contains('minus ₹12,34,56,789.01'));
    expect(semantics.label, contains('Needs review'));
  });
}
