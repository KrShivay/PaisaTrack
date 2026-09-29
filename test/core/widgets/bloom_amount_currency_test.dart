import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/bloom/bloom_amount.dart';

void main() {
  testWidgets('compact USD formatting keeps the currency code suffix',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BloomAmount(
            amount: 12.34,
            currencyCode: 'USD',
            currencySymbol: r'$',
            showPaise: false,
          ),
        ),
      ),
    );

    expect(find.text(r'$12 USD'), findsOneWidget);
  });
}
