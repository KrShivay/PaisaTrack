import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';
import 'package:paisatrack/features/settings/payee_labels_screen.dart';
import 'package:paisatrack/enrichment/merchant_clusterer.dart';

import 'payee_test_helpers.dart';

void main() {
  testWidgets('PayeeLabelsScreen reviews duplicate suggestions without merging',
      (tester) async {
    final database = newPayeeTestDatabase();
    addTearDown(database.close);
    final repository = FakePayeeLabelRepository(
      database,
      items: const [],
      suggestions: const [
        MerchantClusterSuggestion(
          clusterId: 'cluster_1',
          canonicalName: 'Coffee',
          memberMerchantIds: ['merchant_1', 'merchant_2'],
          similarityScore: 0.9,
        ),
      ],
    );
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

    expect(find.text('Possible duplicate payees'), findsOneWidget);
    final mergeBtn = find.byKey(const ValueKey('merge_cluster_button'));
    expect(mergeBtn, findsOneWidget);

    await tester.tap(mergeBtn);
    await tester.pumpAndSettle();

    final confirmBtn =
        find.byKey(const ValueKey('confirm_merge_cluster_button'));
    expect(confirmBtn, findsOneWidget);

    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.text('No payee changes were made.'), findsOneWidget);
  });
}
