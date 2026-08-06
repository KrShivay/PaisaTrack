import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';
import 'package:paisatrack/features/settings/payee_labels_screen.dart';

import 'payee_test_helpers.dart';

void main() {
  testWidgets(
      'PayeeLabelsScreen shows backfill action and opens preview dialog',
      (tester) async {
    final database = newPayeeTestDatabase();
    addTearDown(database.close);
    final repository = FakePayeeLabelRepository(database, items: const []);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payeeLabelRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: const MaterialApp(
          home: PayeeLabelsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backfillBtn = find.byKey(const ValueKey('backfill_payees_button'));
    expect(backfillBtn, findsOneWidget);

    await tester.tap(backfillBtn);
    await tester.pumpAndSettle();

    expect(find.text('Backfill Structured Payees'), findsOneWidget);
    expect(find.byKey(const ValueKey('apply_backfill_button')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('apply_backfill_button')));
    await tester.pumpAndSettle();

    expect(find.text('Backfill preview applied cleanly.'), findsOneWidget);
  });
}
