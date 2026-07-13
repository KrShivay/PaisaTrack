import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/core/widgets/correction_scope_sheet.dart';
import 'package:paisatrack/data/repositories/category_correction.dart';

void main() {
  test('scope defaults match correction context', () {
    expect(
      defaultCorrectionScope(CorrectionContext.oneOffEdit),
      CorrectionScope.thisTransaction,
    );
    expect(
      defaultCorrectionScope(CorrectionContext.newMerchant),
      CorrectionScope.futureMatching,
    );
    expect(
      defaultCorrectionScope(CorrectionContext.groupReview),
      CorrectionScope.matchingGroup,
    );
    expect(
      defaultCorrectionScope(CorrectionContext.historicalCleanup),
      CorrectionScope.existingAndFuture,
    );
    expect(
      defaultCorrectionScope(CorrectionContext.existingRule),
      CorrectionScope.updateFutureRule,
    );
  });

  testWidgets('shows explicit scope choices and returns the selection',
      (tester) async {
    CorrectionScope? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                selected = await showCorrectionScopeSheet(
                  context: context,
                  categoryName: 'Food & Dining',
                  availableScopes: const {
                    CorrectionScope.thisTransaction,
                    CorrectionScope.futureMatching,
                    CorrectionScope.existingAndFuture,
                    CorrectionScope.matchingGroup,
                  },
                  initialScope: CorrectionScope.matchingGroup,
                  matchingCount: 22,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Apply Food & Dining to:'), findsOneWidget);
    expect(find.text('This transaction only'), findsOneWidget);
    expect(
      find.text('Future transactions from this merchant'),
      findsOneWidget,
    );
    expect(
      find.text('Existing and future matching transactions'),
      findsOneWidget,
    );
    expect(
      find.text('Matching transactions in this group (22)'),
      findsOneWidget,
    );

    await tester.tap(find.text('This transaction only'));
    await tester.tap(find.text('Apply category'));
    await tester.pumpAndSettle();
    expect(selected, CorrectionScope.thisTransaction);
  });
}
