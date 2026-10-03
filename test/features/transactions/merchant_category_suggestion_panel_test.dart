import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/merchant_category_suggestion_repository.dart';
import 'package:paisatrack/features/transactions/detail/merchant_category_suggestion_panel.dart';

void main() {
  testWidgets('explains category history and accepts the suggestion',
      (tester) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantCategorySuggestionPanel(
            suggestion: const MerchantCategorySuggestion(
              categoryId: 'food',
              categoryName: 'Food',
              supportingTransactionCount: 3,
            ),
            onAccept: () => accepted = true,
          ),
        ),
      ),
    );

    expect(find.text('Based on your past category choices'), findsOneWidget);
    expect(
      find.text('3 prior transactions for this payee have this category.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Use Food'));
    expect(accepted, isTrue);
  });

  testWidgets('disables rapid repeat acceptance while saving', (tester) async {
    var accepted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MerchantCategorySuggestionPanel(
            suggestion: const MerchantCategorySuggestion(
              categoryId: 'food',
              categoryName: 'Food',
              supportingTransactionCount: 2,
            ),
            isSaving: true,
            onAccept: () => accepted = true,
          ),
        ),
      ),
    );

    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Saving…'));
    expect(accepted, isFalse);
  });
}
