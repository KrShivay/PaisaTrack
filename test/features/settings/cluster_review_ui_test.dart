import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisatrack/data/repositories/payee_label_repository.dart';
import 'package:paisatrack/features/settings/payee_labels_screen.dart';

void main() {
  testWidgets('PayeeLabelsScreen shows cluster suggestion banner and merges cluster with one action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          payeeIdentitiesProvider.overrideWith((ref) => Stream.value(<PayeeIdentity>[])),
        ],
        child: const MaterialApp(
          home: PayeeLabelsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Suggested Merchant Cluster'), findsOneWidget);
    final mergeBtn = find.byKey(const ValueKey('merge_cluster_button'));
    expect(mergeBtn, findsOneWidget);

    await tester.tap(mergeBtn);
    await tester.pumpAndSettle();

    final confirmBtn = find.byKey(const ValueKey('confirm_merge_cluster_button'));
    expect(confirmBtn, findsOneWidget);

    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(find.text('Cluster merged cleanly and rule updated.'), findsOneWidget);
  });
}
